#include <fstream>
#include <memory>
#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <unordered_map>
#include <iostream>

#include "llvm-c/Core.h"

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/LinkAllPasses.h"
#include "llvm/Support/ManagedStatic.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Analysis/InstructionSimplify.h"
#include "llvm/Analysis/CallGraph.h"
//#include "llvm/Analysis/AnalysisManager.h"

#include "llvm/IR/LLVMContext.h"

#include "llvm/IR/Module.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Pass.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Analysis/CallGraph.h"
#include "llvm/Support/SourceMgr.h"
#include <memory>

using namespace llvm;

static void DoInlining(Module *);

static void summarize(Module *M);

static void print_csv_file(std::string outputfile);

static cl::opt<std::string>
        InputFilename(cl::Positional, cl::desc("<input bitcode>"), cl::Required, cl::init("-"));

static cl::opt<std::string>
        OutputFilename(cl::Positional, cl::desc("<output bitcode>"), cl::Required, cl::init("out.bc"));

static cl::opt<bool>
        InlineHeuristic("inline-heuristic",
              cl::desc("Use student's inlining heuristic."),
              cl::init(false));

static cl::opt<bool>
        InlineConstArg("inline-require-const-arg",
              cl::desc("Require function call to have at least one constant argument."),
              cl::init(false));

static cl::opt<int>
        InlineFunctionSizeLimit("inline-function-size-limit",
              cl::desc("Biggest size of function to inline."),
              cl::init(1000000000));

static cl::opt<int>
        InlineGrowthFactor("inline-growth-factor",
              cl::desc("Largest allowed program size increase factor (e.g. 2x)."),
              cl::init(20));


static cl::opt<bool>
        NoInline("no-inline",
              cl::desc("Do not perform inlining."),
              cl::init(false));


static cl::opt<bool>
        NoPreOpt("no-preopt",
              cl::desc("Do not perform pre-inlining optimizations."),
              cl::init(false));

static cl::opt<bool>
        NoPostOpt("no-postopt",
              cl::desc("Do not perform post-inlining optimizations."),
              cl::init(false));

static cl::opt<bool>
        Verbose("verbose",
                    cl::desc("Verbose stats."),
                    cl::init(false));

static cl::opt<bool>
        NoCheck("no",
                cl::desc("Do not check for valid IR."),
                cl::init(false));


static llvm::Statistic nInstrBeforeOpt = {"", "nInstrBeforeOpt", "number of instructions"};
static llvm::Statistic nInstrBeforeInline = {"", "nInstrPreInline", "number of instructions"};
static llvm::Statistic nInstrAfterInline = {"", "nInstrAfterInline", "number of instructions"};
static llvm::Statistic nInstrPostOpt = {"", "nInstrPostOpt", "number of instructions"};


static void countInstructions(Module *M, llvm::Statistic &nInstr) {
  for (auto i = M->begin(); i != M->end(); i++) {
    for (auto j = i->begin(); j != i->end(); j++) {
      for (auto k = j->begin(); k != j->end(); k++) {
	nInstr++;
      }
    }
  }
}


int main(int argc, char **argv) {
    // Parse command line arguments
    cl::ParseCommandLineOptions(argc, argv, "llvm system compiler\n");

    // Handle creating output files and shutting down properly
    llvm_shutdown_obj Y;  // Call llvm_shutdown() on exit.
    LLVMContext Context;

    // LLVM idiom for constructing output file.
    std::unique_ptr<ToolOutputFile> Out;
    std::string ErrorInfo;
    std::error_code EC;
    Out.reset(new ToolOutputFile(OutputFilename.c_str(), EC,
                                 sys::fs::OF_None));

    EnableStatistics();

    // Read in module
    SMDiagnostic Err;
    std::unique_ptr<Module> M;
    M = parseIRFile(InputFilename, Err, Context);

    // If errors, fail
    if (M.get() == 0)
    {
        Err.print(argv[0], errs());
        return 1;
    }

    countInstructions(M.get(),nInstrBeforeOpt);
    
    if (!NoPreOpt) {
      legacy::PassManager Passes;
      Passes.add(createPromoteMemoryToRegisterPass());    
      Passes.add(createEarlyCSEPass());
      Passes.add(createSCCPPass());
      Passes.add(createAggressiveDCEPass());
      Passes.add(createVerifierPass());
      Passes.run(*M);  
    }

    countInstructions(M.get(),nInstrBeforeInline);    

    if (!NoInline) {
        DoInlining(M.get());
    }

    countInstructions(M.get(),nInstrAfterInline);
    
    if (!NoPostOpt) {
      legacy::PassManager Passes;
      Passes.add(createPromoteMemoryToRegisterPass());    
      Passes.add(createEarlyCSEPass());
      Passes.add(createSCCPPass());
      Passes.add(createAggressiveDCEPass());
      Passes.add(createVerifierPass());
      Passes.run(*M);  
    }

    countInstructions(M.get(),nInstrPostOpt);
    
    // Collect statistics on Module
    summarize(M.get());
    print_csv_file(OutputFilename);

    if (Verbose)
        PrintStatistics(errs());

    // Verify integrity of Module, do this by default
    if (!NoCheck)
    {
        legacy::PassManager Passes;
        Passes.add(createVerifierPass());
        Passes.run(*M.get());
    }

    // Write final bitcode
    WriteBitcodeToFile(*M.get(), Out->os());
    Out->keep();

    return 0;
}

static llvm::Statistic nFunctions = {"", "Functions", "number of functions"};
static llvm::Statistic nInstructions = {"", "Instructions", "number of instructions"};
static llvm::Statistic nLoads = {"", "Loads", "number of loads"};
static llvm::Statistic nStores = {"", "Stores", "number of stores"};

static void summarize(Module *M) {
    for (auto i = M->begin(); i != M->end(); i++) {
        if (i->begin() != i->end()) {
            nFunctions++;
        }

        for (auto j = i->begin(); j != i->end(); j++) {
            for (auto k = j->begin(); k != j->end(); k++) {
                Instruction &I = *k;
                nInstructions++;
                if (isa<LoadInst>(&I)) {
                    nLoads++;
                } else if (isa<StoreInst>(&I)) {
                    nStores++;
                }
            }
        }
    }
}

static void print_csv_file(std::string outputfile)
{
    std::ofstream stats(outputfile + ".stats");
    auto a = GetStatistics();
    for (auto p : a) {
        stats << p.first.str() << "," << p.second << std::endl;
    }
    stats.close();
}

static llvm::Statistic Inlined = {"", "Inlined", "Inlined a call."};
static llvm::Statistic ConstArg = {"", "ConstArg", "Call has a constant argument."};
static llvm::Statistic SizeReq = {"", "SizeReq", "Call has a constant argument."};


#include "llvm/Transforms/Utils/Cloning.h"

//Function to check whether the instruction is a call or not. Returns True for Call instruction and False for others.
bool isCall(Instruction *I)
{
  //Getting the opcode of the instruction
  int opcode = I->getOpcode();
  //If opcode is a Call instruction, then return True;
  if(opcode == Instruction::Call)
  {
    return true;
  }
  else
  {
    return false;
  }
}
// Implement a function to perform function inlining
static void DoInlining(Module *M) {
  //ECE566 - Advanced Heuristic. If this flag is True from the command line, then only this particular heuristic is executed.
  // The heuristic is that, the most frequently called functions are inlined compared to less frequently called function.
  if(InlineHeuristic)
  {
    //Inline the function calls that are called more than the threshold value.
    int threshold = 2;
    //A Map to store the number of calls of a function corresponding to function name.
    std::map<std::string, int> func_uses_map;
    LLVMValueRef  fn_iter; // iterator 
    LLVMModuleRef mod = wrap(M);
    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; 
        fn_iter = LLVMGetNextFunction(fn_iter))
    {
     //Casting function iterator to a Function *
     Function* fn = dyn_cast<Function>(unwrap(fn_iter)); 
     int uses = 0;
     for (auto use_it = fn->user_begin(); use_it != fn->user_end(); ++use_it)
     {
        //Getting the uses of the corresponding function.
        ++uses;
     }
     //Storing the uses corresponding to the function name.
     func_uses_map[std::string(LLVMGetValueName(fn_iter))] = uses;
    }

    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; 
        fn_iter = LLVMGetNextFunction(fn_iter))
    {
      // fn_iter points to a function
      LLVMBasicBlockRef bb_iter; /* points to each basic block one at a time */
      for (bb_iter = LLVMGetFirstBasicBlock(fn_iter);
      bb_iter != NULL; bb_iter = LLVMGetNextBasicBlock(bb_iter))
      {   
        LLVMValueRef inst_iter = LLVMGetFirstInstruction(bb_iter);
        //Traversing through the instructions in a basic block.
        while(inst_iter != NULL) 
        {
          //Checking if the instruction is a call or not.
          if(isCall(dyn_cast<Instruction>(unwrap(inst_iter))))
          {
            //Getting the function name to check for the functions defined within a module, 
            //only those can be inlined
            Function* CalledFunction = dyn_cast<CallInst>(unwrap(inst_iter))->getCalledFunction();
            //If the Called Function is not NULL and belong to the scurrent module then we perform inlining.
            if (CalledFunction && (CalledFunction->getParent() == M)) {
              // The called function is defined within the module, add it to the worklist
              //Check if the function is not just a declaration by counting the basic blocks.
              int numBBs = 0;
              for (Function::iterator bb = CalledFunction->begin(), e = CalledFunction->end(); bb != e; ++bb) {
                ++numBBs;
              }

              if(numBBs != 0)
              {
                //If the number of calls is greater than threshold, then perform the inline
                if(func_uses_map[CalledFunction->getName().str()] > threshold)
                {
                  InlineFunctionInfo IFI;
                  //Check if the function is not a recursion.
                  InlineResult IR = isInlineViable(*CalledFunction);
                  if(IR.isSuccess())
                  {
                    //Perform Inlining.
                    CallInst *call_instr = dyn_cast<CallInst>(unwrap(inst_iter));
                    InlineFunction(*call_instr, IFI);
                    Inlined++;
                    
                  }
                }

              }
              
            }
          }
          //Iteratoring to the next instruction in the basic block.
          inst_iter = LLVMGetNextInstruction(inst_iter);
        }
      }
    } 
  }

  //Perform Inlining using the worklist based approach.
  else
  {
    //Creating a Worklist to store the instructions using a queue.
    std::queue<LLVMValueRef> Worklist;
    int original_num_instr = 0;
    LLVMModuleRef mod = wrap(M);
    LLVMValueRef  fn_iter; // iterator 
    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; 
        fn_iter = LLVMGetNextFunction(fn_iter))
    {
      // fn_iter points to a function
      LLVMBasicBlockRef bb_iter; /* points to each basic block one at a time */
      for (bb_iter = LLVMGetFirstBasicBlock(fn_iter);
      bb_iter != NULL; bb_iter = LLVMGetNextBasicBlock(bb_iter))
      {
          
        LLVMValueRef inst_iter = LLVMGetFirstInstruction(bb_iter);
        while(inst_iter != NULL) 
        {
          //Checking if the instruction is a call or not
          if(isCall(dyn_cast<Instruction>(unwrap(inst_iter))))
          {
            //Getting the function name to check for the functions defined within a module, 
            //only those can be inlined
            Function* CalledFunction = dyn_cast<CallInst>(unwrap(inst_iter))->getCalledFunction();
            
            if (CalledFunction && (CalledFunction->getParent() == M)) {
              // The called function is defined within the module, add it to the worklist
              //Checking if the function is not just a declaration and has basic blocks.
              int numBBs = 0;
              for (Function::iterator bb = CalledFunction->begin(), e = CalledFunction->end(); bb != e; ++bb) {
                ++numBBs;
              }

              if(numBBs != 0)
              {
                Worklist.push(inst_iter);
              }
              
            }
          }
          original_num_instr++;
          inst_iter = LLVMGetNextInstruction(inst_iter);
        }
      }
    }

    //A map to store number of instructions for each function
    std::map<std::string, int> func_num_instr_map; 
    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; 
        fn_iter = LLVMGetNextFunction(fn_iter))
    {
      int num_instr = 0; // number of instructions count variable.
      // fn_iter points to a function
      LLVMBasicBlockRef bb_iter; /* points to each basic block one at a time */
      for (bb_iter = LLVMGetFirstBasicBlock(fn_iter);
      bb_iter != NULL; bb_iter = LLVMGetNextBasicBlock(bb_iter))
      {
        LLVMValueRef inst_iter = LLVMGetFirstInstruction(bb_iter);
        while(inst_iter != NULL) 
        {
          //Counting the number of instructions in a function
          num_instr ++;
          inst_iter = LLVMGetNextInstruction(inst_iter);
        }
      }

      func_num_instr_map[std::string(LLVMGetValueName(fn_iter))] = num_instr;
    }

    int current_instr_count = original_num_instr;
    while(!Worklist.empty())
    {
      //Inline the calls based on the conditions until worklist is not empty.
      LLVMValueRef inst_iter = Worklist.front();
      Worklist.pop();

      CallInst *call_instr = dyn_cast<CallInst>(unwrap(inst_iter));
      Function *call_func = call_instr->getCalledFunction();

      std::string function_name = call_func->getName().str();
      //Checking for number of instructions inside a function.
      if(func_num_instr_map[function_name] < InlineFunctionSizeLimit)
      {
        SizeReq++;
        //Checking for the growth factor
        current_instr_count = current_instr_count + func_num_instr_map[function_name] - 1;
        func_num_instr_map[function_name] = current_instr_count;
        if(current_instr_count < (original_num_instr * (InlineGrowthFactor)))
        {
          //Checking if the function has any argument as constant.
          bool hasconstant = false;
          if(InlineConstArg)
          {
            //Check arguments of the call instruction and not the calling function.
            for(auto args = call_instr->arg_begin(); args != call_instr->arg_end(); args++)
            {
              if (isa<Constant>(args))
              {
                ConstArg++;
                hasconstant = true;
                break;
              }
            }
          }
          else
          {
            //If the costant condition is disabled, we set it to true for all the instructions.
            hasconstant = true;
          }
          //If the 3 conditions are satisfied based on the command line arguments, then we perform the inlining.
          if(hasconstant)
          {
            InlineFunctionInfo IFI;
            InlineResult IR = isInlineViable(*call_func);
            if(IR.isSuccess())
            {
              //Perform Inlining
              InlineFunction(*call_instr, IFI);
              Inlined++;
            }
          }
        }      
      }
    }
  }

}
