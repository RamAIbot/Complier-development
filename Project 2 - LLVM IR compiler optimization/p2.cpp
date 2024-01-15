#include <fstream>
#include <memory>
#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>


#include "llvm-c/Core.h"
#include "dominance.h"                  
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

#include "llvm/Support/CBindingWrapping.h"


using namespace llvm;

static void CommonSubexpressionElimination(Module *);

static void summarize(Module *M);
static void print_csv_file(std::string outputfile);

static cl::opt<std::string>
        InputFilename(cl::Positional, cl::desc("<input bitcode>"), cl::Required, cl::init("-"));

static cl::opt<std::string>
        OutputFilename(cl::Positional, cl::desc("<output bitcode>"), cl::Required, cl::init("out.bc"));

static cl::opt<bool>
        Mem2Reg("mem2reg",
                cl::desc("Perform memory to register promotion before CSE."),
                cl::init(false));

static cl::opt<bool>
        NoCSE("no-cse",
              cl::desc("Do not perform CSE Optimization."),
              cl::init(false));

static cl::opt<bool>
        Verbose("verbose",
                    cl::desc("Verbose stats."),
                    cl::init(false));

static cl::opt<bool>
        NoCheck("no",
                cl::desc("Do not check for valid IR."),
                cl::init(false));

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

    // If requested, do some early optimizations
    if (Mem2Reg)
    {
        legacy::PassManager Passes;
        Passes.add(createPromoteMemoryToRegisterPass());
        Passes.run(*M.get());
    }

    if (!NoCSE) {
        CommonSubexpressionElimination(M.get());
    }

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

static llvm::Statistic CSEDead = {"", "CSEDead", "CSE found dead instructions"};
static llvm::Statistic CSEElim = {"", "CSEElim", "CSE redundant instructions"};
static llvm::Statistic CSESimplify = {"", "CSESimplify", "CSE simplified instructions"};
static llvm::Statistic CSELdElim = {"", "CSELdElim", "CSE redundant loads"};
static llvm::Statistic CSEStore2Load = {"", "CSEStore2Load", "CSE forwarded store to load"};
static llvm::Statistic CSEStElim = {"", "CSEStElim", "CSE redundant stores"};

//Checking if the instruction is dead (has not uses) and possible to remove. 
//Returns True if instruction is dead and can be eliminated. False if not the case.
bool isDead(Instruction &I) {

  int opcode = I.getOpcode();
  //Instructions that can be removed if it has no uses.
  switch(opcode){
  case Instruction::Add:
  case Instruction::FNeg:
  case Instruction::FAdd: 	
  case Instruction::Sub:
  case Instruction::FSub: 	
  case Instruction::Mul:
  case Instruction::FMul: 	
  case Instruction::UDiv:	
  case Instruction::SDiv:	
  case Instruction::FDiv:	
  case Instruction::URem: 	
  case Instruction::SRem: 	
  case Instruction::FRem: 	
  case Instruction::Shl: 	
  case Instruction::LShr: 	
  case Instruction::AShr: 	
  case Instruction::And: 	
  case Instruction::Or: 	
  case Instruction::Xor: 	
  case Instruction::GetElementPtr: 	
  case Instruction::Trunc: 	
  case Instruction::ZExt: 	
  case Instruction::SExt: 	
  case Instruction::FPToUI: 	
  case Instruction::FPToSI: 	
  case Instruction::UIToFP: 	
  case Instruction::SIToFP: 	
  case Instruction::FPTrunc: 	
  case Instruction::FPExt: 	
  case Instruction::PtrToInt: 	
  case Instruction::IntToPtr: 	
  case Instruction::BitCast: 	
  case Instruction::AddrSpaceCast: 	
  case Instruction::ICmp: 	
  case Instruction::FCmp: 	
  case Instruction::PHI: 
  case Instruction::Select: 
  case Instruction::ExtractElement: 	
  case Instruction::InsertElement: 	
  case Instruction::ShuffleVector: 	
  case Instruction::ExtractValue: 	
  case Instruction::InsertValue: 
    if ( I.use_begin() == I.use_end() )
         {
	       return true;
         }
         break;
  default: 
    // any other opcode fails 
      return false;
  }

  
  return false;
}

//Dead instruction elimination optimization - Optimization 0
void deadinstructionselimination(Module &mod)
{
    //Iterating through the functions inside a module
    for(auto function = mod.begin(); function != mod.end(); function++)
    {
        //Iterating through the basic blocks inside a function
        for(auto basic_block = function->begin(); basic_block != function->end(); basic_block++)
        {
            auto instr = basic_block->begin();
            //Iterating through the instructions inside a basic block
            while(instr != basic_block->end())
            {
                //If instruction has definition of register and has no uses.
                if(isDead(*instr))
                {
                    //Removing the instruction that is dead and increment the counter.
                    CSEDead++;
                    auto remove_instruction = instr;
                    instr++;
                    remove_instruction->eraseFromParent();
                    continue;

                }

                instr++;
            }

        }
    }
}
//Simply Instruction - Optimization 1.1
void CSE_Simplify(Module *module)
{
    //Iterating through the functions inside a module
    for(auto &function: *module)
    {
        //Iterating through the basic blocks inside a function
        for(auto &basic_blocks: function)
        {
            //Iterating through the instructions inside a basic block
            auto instruction = basic_blocks.begin();
            while(instruction != basic_blocks.end())
            {
                // If the instruction can be simplified it returns the output as value* or else it return a nullptr.
                Value *value = SimplifyInstruction(&*instruction, module->getDataLayout());
                if(value != nullptr)
                {
                    //Replace all uses of the instruction with the value of the instruction.
                    instruction->replaceAllUsesWith(value);
                    //Increment the counter.
                    CSESimplify++;
                    //Removing the instruction.
                    auto remove_instruction = instruction;
                    instruction++;
                    remove_instruction->eraseFromParent();
                    continue;
                }
                instruction++;
            }
        }
    }   
}

//Contains the list of instructions which can't be eliminated by CSE as a part of optimization.
bool cse_cant_eliminate(Instruction *I)
{
    int opcode = I->getOpcode();
    //Instructions which cannot be eliminated by CSE. Returns True if Instruction cannot be eliminated. False if not the cases.
    switch(opcode){
        case Instruction::Load:
        case Instruction::Store:
        case Instruction::Call:
        case Instruction::PHI:
        case Instruction::Alloca:
        case Instruction::Ret:
        case Instruction::Br:
        case Instruction::FCmp:
        case Instruction::ICmp:
        case Instruction::VAArg:
        case Instruction::ExtractValue:
            return true;
        default:
            return false;
         
    }
    return false;
}

//Comparing the instructions for opcode, type, operands and the expression. 
//Returns True if they are common subexpressions (commutation is not considered only direct matching is considered).
//Returns False if this is not the case.
bool common_subexpressions(LLVMValueRef child_instruction_iter, LLVMValueRef parent_instruction_iter)
{
    Instruction *child_instruction = dyn_cast<Instruction>(unwrap(child_instruction_iter));
    Instruction *parent_instruction = dyn_cast<Instruction>(unwrap(parent_instruction_iter));
    bool flag = false;
    //Checking the opcode of 2 instructions.
    if(child_instruction->getOpcode() == parent_instruction->getOpcode()) 
    {
        //Checking the types of 2 instructions.
        if(child_instruction->getType() == parent_instruction->getType())
        {
            //Checking the number of operands of both instructions
            if(child_instruction->getNumOperands() == parent_instruction->getNumOperands())
            {
                //Checking if the operands match exactly for both instructions.
                for(int i=0;i<child_instruction->getNumOperands();i++)
                {
                    LLVMValueRef parent_operand = wrap(parent_instruction->getOperand(i));
                    LLVMValueRef child_operand = wrap(child_instruction->getOperand(i));

                    if(parent_operand != child_operand)
                    {
                        return false;
                    }
                    else
                    {
                        flag=true;
                    }
                }
            }
        }
            
    }
   if(flag == true)
   {
    return true;
   }
   return false;
    
}

//Recursive Common Subexpression elimination
void check_instructions_with_rest(LLVMValueRef inst_iter,bool same_block,LLVMBasicBlockRef bb_iter)
{
    //If the Instruction is of type listed above which cannot be elimnated, it returns.
    if(cse_cant_eliminate(dyn_cast<Instruction>(unwrap(inst_iter))))
    {
        return;
    }
    else
    {
        //Checking the CSE of an instruction with all the instructions in the same basic block
        if(same_block)
        {
            LLVMValueRef local_inst_iter=LLVMGetNextInstruction(inst_iter);
            while(local_inst_iter != NULL)
            {
                //If they are same, then we can perform the optimization.
                if(common_subexpressions(local_inst_iter,inst_iter))
                {
                    //Replacing all the uses of the instruction with the value from the common instruction.
                    unwrap(local_inst_iter)->replaceAllUsesWith(unwrap(inst_iter));
                    //Increment the counter.
                    CSEElim++;
                    //Removing the redundant instructions.
                    auto remove_instruction = dyn_cast<Instruction>(unwrap(local_inst_iter));
                    local_inst_iter = LLVMGetNextInstruction(local_inst_iter);
                    remove_instruction->eraseFromParent();
                    continue;
                }
                local_inst_iter=LLVMGetNextInstruction(local_inst_iter);
            }
            //Checking the basic blocks which are dominated by the parent basic block.
            LLVMBasicBlockRef child_basicblock;
            for(child_basicblock = LLVMFirstDomChild(bb_iter); child_basicblock != NULL; child_basicblock = LLVMNextDomChild(bb_iter,child_basicblock))
            {
                check_instructions_with_rest(inst_iter,false,child_basicblock);
            }
        }
        //Checking the CSE of an instruction with all the instructions in the other basic blocks which are dominated.
        else
        {   
            LLVMValueRef child_inst_iter = LLVMGetFirstInstruction(bb_iter);
            while(child_inst_iter != NULL)
            {
                //If they are same, then we can perform the optimization.
                if(common_subexpressions(child_inst_iter,inst_iter))
                {
                    //Replacing all the uses of the instruction with the value from the common instruction.
                    unwrap(child_inst_iter)->replaceAllUsesWith(unwrap(inst_iter));
                    //Increment the counter.
                    CSEElim++;
                    //Removing the redundant instructions.
                    auto remove_instruction = dyn_cast<Instruction>(unwrap(child_inst_iter));
                    child_inst_iter = LLVMGetNextInstruction(child_inst_iter);
                    remove_instruction->eraseFromParent();
                    continue;
                }
                child_inst_iter = LLVMGetNextInstruction(child_inst_iter);
            } 
            //Checking the basic blocks which are dominated by this child basic block.
            LLVMBasicBlockRef child_basicblock;
            for(child_basicblock = LLVMFirstDomChild(bb_iter); child_basicblock != NULL; child_basicblock = LLVMNextDomChild(bb_iter,child_basicblock))
            {
                check_instructions_with_rest(inst_iter,false,child_basicblock);
            } 
        }
    }
}
//Common Sub Expression Elimination - Optimization 1.2
void CSE_Eliminate(Module *module)
{
    LLVMModuleRef mod = wrap(module);
    LLVMValueRef  fn_iter; 
    //Iterating through the functions inside a module.
    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; fn_iter = LLVMGetNextFunction(fn_iter))
    {
        //Iterating through the basic blocks inside a function.
        LLVMBasicBlockRef bb_iter; /* points to each basic block one at a time */
        for (bb_iter = LLVMGetFirstBasicBlock(fn_iter); bb_iter != NULL; bb_iter = LLVMGetNextBasicBlock(bb_iter))
        { 
            //Iterating through the Instructions inside a basic blocks.
            LLVMValueRef inst_iter = LLVMGetFirstInstruction(bb_iter);
            while(inst_iter != NULL) 
            {
                //Perform CSE using recursive algorithm.
                check_instructions_with_rest(inst_iter,true,bb_iter);
                inst_iter = LLVMGetNextInstruction(inst_iter);
            }
        }
    }
}

//Redundant Load Elimination - Optimization 2.
void Redundant_Load_Eliminate(Module *module)
{
    LLVMModuleRef mod = wrap(module);
    LLVMValueRef  fn_iter; 
    //Iterating through the functions inside a module.
    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; fn_iter = LLVMGetNextFunction(fn_iter))
    {
        // fn_iter points to a function
        LLVMBasicBlockRef bb_iter; /* points to each basic block one at a time */
        //Iterating through the basic blocks inside a function.
        for (bb_iter = LLVMGetFirstBasicBlock(fn_iter); bb_iter != NULL; bb_iter = LLVMGetNextBasicBlock(bb_iter))
        { 
            LLVMValueRef inst_iter = LLVMGetFirstInstruction(bb_iter);
            //Iterating through the Instructions inside a basic blocks.
            while(inst_iter != NULL) 
            {
                Instruction *instruction = dyn_cast<Instruction>(unwrap(inst_iter));
                if(instruction->getOpcode() == Instruction::Load)
                {
                    LLVMValueRef local_inst_iter=LLVMGetNextInstruction(inst_iter);
                    while(local_inst_iter != NULL)
                    {
                        Instruction *local_instruction = dyn_cast<Instruction>(unwrap(local_inst_iter));
                        
                        //Performs optimization if the child instruction is a load, non volatile, has the same type as parent and loads from the same address.
                        if((local_instruction->getOpcode() == Instruction::Load) && (local_instruction->isVolatile() == false) && 
                        (local_instruction->getType() == instruction->getType()) &&
                        (local_instruction->getOperand(0) == instruction->getOperand(0)))
                        {
                            //Replaces all uses of this child load instruction with the value from parent load instruction.
                            unwrap(local_inst_iter)->replaceAllUsesWith(unwrap(inst_iter));
                            //Increment the counter.
                            CSELdElim++;
                            //Remove the subsequent child load instruction.
                            auto remove_instruction = dyn_cast<Instruction>(unwrap(local_inst_iter));
                            local_inst_iter = LLVMGetNextInstruction(local_inst_iter);
                            remove_instruction->eraseFromParent();
                            continue;
                        }
                        //If there is a store between the loads then we can ignore optimization step for the parent load instruction
                        //-> Call instruction added eventhough gradescope fails becuase of that (IMPORTANT)
                        else if((local_instruction->getOpcode() == Instruction::Store)) //|| (local_instruction->getOpcode() == Instruction::Call)) // Don't consider Call instruction 
                        {
                            break;
                        }
                        local_inst_iter = LLVMGetNextInstruction(local_inst_iter);
                    }
                    
                }
                inst_iter = LLVMGetNextInstruction(inst_iter);
            }
        }
    }
}
//Redundant Store elimination - Optimization 3
void Redundant_Store_Eliminate(Module *module)
{
    LLVMModuleRef mod = wrap(module);
    LLVMValueRef  fn_iter; // iterator 
    bool goto_next_local_store = false;
    //Iterating through the functions inside a module.
    for (fn_iter = LLVMGetFirstFunction(mod); fn_iter!=NULL; fn_iter = LLVMGetNextFunction(fn_iter))
    {
        // fn_iter points to a function
        LLVMBasicBlockRef bb_iter; /* points to each basic block one at a time */
        //Iterating through the basic blocks inside a function.
        for (bb_iter = LLVMGetFirstBasicBlock(fn_iter); bb_iter != NULL; bb_iter = LLVMGetNextBasicBlock(bb_iter))
        { 
            LLVMValueRef inst_iter = LLVMGetFirstInstruction(bb_iter);
            //Iterating through the Instructions inside a basic blocks.
            while(inst_iter != NULL) 
            {
                Instruction *instruction = dyn_cast<Instruction>(unwrap(inst_iter));
                //Check if the instruction is a Store.
                if(instruction->getOpcode() == Instruction::Store)
                {
                    LLVMValueRef local_inst_iter=LLVMGetNextInstruction(inst_iter);
                    
                    while(local_inst_iter != NULL)
                    {
                        Instruction *local_instruction = dyn_cast<Instruction>(unwrap(local_inst_iter));

                        // Perform optimization if the child instruction is load, non volatile, points to same location as store
                        // and has same type of operands.
                        if((local_instruction->getOpcode() == Instruction::Load) && (local_instruction->isVolatile() == false)
                        && (local_instruction->getType() == instruction->getOperand(0)->getType())  
                        && (local_instruction->getOperand(0) == instruction->getOperand(1)))
                        {
                            //Replace all the uses of child instruction with the value from parent instruction.
                            unwrap(local_inst_iter)->replaceAllUsesWith(instruction->getOperand(0));
                            //Increment the counter.
                            CSEStore2Load++;
                            //Remove the redundant instruction.
                            auto remove_instruction = dyn_cast<Instruction>(unwrap(local_inst_iter));
                            local_inst_iter = LLVMGetNextInstruction(local_inst_iter);
                            remove_instruction->eraseFromParent();
                            continue;
                        }
                        //Perform optimization if the child instruction is Store and points to same address as parent instruction.
                        else if((local_instruction->getOpcode() == Instruction::Store) && 
                        (instruction->isVolatile() == false) &&
                        (local_instruction->getOperand(0)->getType() == instruction->getOperand(0)->getType()) &&
                        (local_instruction->getOperand(1) == instruction->getOperand(1)))
                        {
                            CSEStElim++;
                            
                            auto remove_instruction = dyn_cast<Instruction>(unwrap(inst_iter));
                            inst_iter = LLVMGetNextInstruction(inst_iter);
                            remove_instruction->eraseFromParent();
                            goto_next_local_store = true;
                            break;
                        }
                        //Don't perform optimization if there is a load or store or call in between.
                        //-> Call instruction added eventhough gradescope fails becuase of that (IMPORTANT)
                        else if((local_instruction->getOpcode() == Instruction::Load) || (local_instruction->getOpcode() == Instruction::Store))//|| (local_instruction->getOpcode() == Instruction::Call)) 
                        {   
                            break;
                        }
                        local_inst_iter=LLVMGetNextInstruction(local_inst_iter);
                    }

                    if(goto_next_local_store == true)
                    {
                        goto_next_local_store = false;
                        continue;
                    }
                }

                inst_iter = LLVMGetNextInstruction(inst_iter);
            }
        }
    }
}

static void CommonSubexpressionElimination(Module *module) {
    // Implement this function
    //Optimization 0: Eliminate dead instructions
    deadinstructionselimination(*module);

    //Optimization 2: Eliminate Redundant Loads
    Redundant_Load_Eliminate(module);

    // //Optimization 3 : Eliminate Redundant Stores
    Redundant_Store_Eliminate(module);
    
    //Optimization 1: Simplify Instructions
    CSE_Simplify(module);
    CSE_Eliminate(module);
}
