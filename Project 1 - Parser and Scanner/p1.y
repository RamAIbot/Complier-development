%{
#include <cstdio>
#include <list>
#include <vector>
#include <map>
#include <iostream>
#include <fstream>
#include <string>
#include <memory>
#include <stdexcept>

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Value.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/Verifier.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Support/FileSystem.h"

using namespace llvm;
using namespace std;


// Need for parser and scanner
extern FILE *yyin;
int yylex();
void yyerror(const char*);
int yyparse();
 
// Needed for LLVM
string funName;
Module *M;
LLVMContext TheContext;
IRBuilder<> Builder(TheContext);

//Map to store the variables and values
static std::map<std::string, Value*> Variable_mappings;
//Map to find out whether the variable is a matrix or a value. True means matrix and False means variable.
std::map<std::string,bool> mat_or_val;
//Vector to store the arguments variable names.
std::vector<std::string> args_vec;
//Map of 2D vectors to store the matrix name and values.
std::map<std::string,std::vector<std::vector<Value*>>> matrices;
//Storing the dimension of the matrix.
int dimensions[2];

//Type definition of 2D vector to pass the matrix to upper level rules of grammar.
typedef std::vector<std::vector<Value*>*> rows2d;
//Type definition of 1D vector to pass the matrix to upper level rules of grammar.
typedef std::vector<Value*> rows;

//struct datatype to find out whether the variable is a value or matrix type
struct var_or_mat
{
  bool is_var=false;
  Value* value=NULL;
  //Storing the matrix name instead of passing pointers
  std::string mat_name;
};
//Performs matrix reduction operation. Returns a Value* type and takes std::string matrix name as argument.
Value* reduction(std::string mat_name)
{
  std::vector<std::vector<Value*> > a = matrices[mat_name];
  Value* result = ConstantFP::get(Type::getFloatTy(TheContext), 0.0);
  for(int i=0;i<a.size();i++)
  {
    for(int j=0;j<a[i].size();j++)
    {
      result = Builder.CreateFAdd(result,a[i][j]);
    }
  }
  return result;
}
//Performs matrix multiplication operation. Returns matrix name of the resultant matrix and takes 2 arguments 
//of type std::string which are the two matrices whose product needs to be computed.
std::string matrix_product(std::string a_mat,std::string b_mat)
{
  std::vector<std::vector<Value*> > a = matrices[a_mat];
  std::vector<std::vector<Value*> > b = matrices[b_mat];
  
  std::vector<std::vector<Value*> > vec;
    
  if(a[0].size() != b.size())
  {
    // If the matrix product size rules doesn't match, it aborts.
    yyerror("Matrix multiplication dimension error\n");
    return "error";
  }
    
  for(int i=0;i<a.size();i++)
  {
      std::vector<Value*> row_vec;
      for(int j=0;j<b[i].size();j++)
      {
        Value* inner_product = ConstantFP::get(Type::getFloatTy(TheContext), 0.0);
        for(int k=0;k<b.size();k++)
        {
          Value* first = a[i][k];
          Value* second = b[k][j];
          Value* product = Builder.CreateFMul(first,second);
          inner_product = Builder.CreateFAdd(inner_product,product);
        }
        row_vec.push_back(inner_product);
      }
      vec.push_back(row_vec);
  }
  std::string name = "temp";
  matrices[name] = vec;
  std::cout<<"Matrix product "<<name<<"\n";
  return name;
}
//Performs matrix determinant operation. Returns a Value* type and takes std::string type which is the 
//matrix name for which this operation needs to be performed.
Value* find_determinant(std::string mat_name)
{
  if(matrices[mat_name].size() == 1)
  {
    return matrices[mat_name][0][0];
  }
  else if(matrices[mat_name].size() == 2)
  {
    Value *a = matrices[mat_name][0][0];
    Value *b = matrices[mat_name][0][1];
    Value *c = matrices[mat_name][1][0];
    Value *d = matrices[mat_name][1][1];

    return Builder.CreateFSub(Builder.CreateFMul(a,d),Builder.CreateFMul(b,c));
  }
  else if(matrices[mat_name].size() == 3)
  {
    
    Value *a = Builder.CreateFMul(matrices[mat_name][1][1],matrices[mat_name][2][2]);
    Value *b = Builder.CreateFMul(matrices[mat_name][2][1],matrices[mat_name][1][2]);

    Value *c = Builder.CreateFMul(matrices[mat_name][1][0],matrices[mat_name][2][2]);
    Value *d = Builder.CreateFMul(matrices[mat_name][2][0],matrices[mat_name][1][2]);

    Value *e = Builder.CreateFMul(matrices[mat_name][1][0],matrices[mat_name][2][1]);
    Value *f = Builder.CreateFMul(matrices[mat_name][2][0],matrices[mat_name][1][1]);

    Value *sub1 = Builder.CreateFSub(a,b);
    Value *sub2 = Builder.CreateFSub(c,d);
    Value *sub3 = Builder.CreateFSub(e,f);

    Value* det0 = Builder.CreateFMul(matrices[mat_name][0][0],sub1);
    Value* det1 = Builder.CreateFMul(matrices[mat_name][0][1],sub2);
    Value* det2 = Builder.CreateFMul(matrices[mat_name][0][2],sub3);

    return Builder.CreateFAdd(Builder.CreateFSub(det0,det1),det2);
    
  }
  else if(matrices[mat_name].size() == 4)
  {
    //determinant of temps
    Value *a = Builder.CreateFMul(matrices[mat_name][2][2],matrices[mat_name][3][3]);
    Value *b = Builder.CreateFMul(matrices[mat_name][3][2],matrices[mat_name][2][3]);
    Value *c = Builder.CreateFMul(matrices[mat_name][2][1],matrices[mat_name][3][3]);
    Value *d = Builder.CreateFMul(matrices[mat_name][3][1],matrices[mat_name][2][3]);

    Value *e = Builder.CreateFMul(matrices[mat_name][2][1],matrices[mat_name][3][2]);
    Value *f = Builder.CreateFMul(matrices[mat_name][3][1],matrices[mat_name][2][2]);
    Value *g = Builder.CreateFMul(matrices[mat_name][2][0],matrices[mat_name][3][3]);
    Value *h = Builder.CreateFMul(matrices[mat_name][3][0],matrices[mat_name][2][3]);

    Value *i = Builder.CreateFMul(matrices[mat_name][2][0],matrices[mat_name][3][2]);
    Value *j = Builder.CreateFMul(matrices[mat_name][3][0],matrices[mat_name][2][2]);
    // Value *k = Builder.CreateFMul(matrices[mat_name][3][1],matrices[mat_name][2][3]);
    Value *l = Builder.CreateFMul(matrices[mat_name][2][0],matrices[mat_name][3][1]);

    Value *m = Builder.CreateFMul(matrices[mat_name][3][0],matrices[mat_name][2][1]);

    Value *sub1 = Builder.CreateFSub(a,b);
    Value *sub2 = Builder.CreateFSub(c,d);
    Value *sub3 = Builder.CreateFSub(e,f);
    Value *sub4 = Builder.CreateFSub(g,h);
    Value *sub5 = Builder.CreateFSub(i,j);
    Value *sub6 = Builder.CreateFSub(l,m);

    Value *det0 = Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(matrices[mat_name][1][1],sub1),Builder.CreateFMul(matrices[mat_name][1][2],sub2)),Builder.CreateFMul(matrices[mat_name][1][3],sub3));
    Value *det1 = Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(matrices[mat_name][1][0],sub1),Builder.CreateFMul(matrices[mat_name][1][2],sub4)),Builder.CreateFMul(matrices[mat_name][1][3],sub5));
    Value *det2 = Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(matrices[mat_name][1][0],sub2),Builder.CreateFMul(matrices[mat_name][1][1],sub4)),Builder.CreateFMul(matrices[mat_name][1][3],sub6));
    Value *det3 = Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(matrices[mat_name][1][0],sub3),Builder.CreateFMul(matrices[mat_name][1][1],sub5)),Builder.CreateFMul(matrices[mat_name][1][2],sub6));
    
    return Builder.CreateFSub(Builder.CreateFAdd(Builder.CreateFSub(det0,det1),det2),det3);
  }
  else
  {
    Value* a = matrices[mat_name][0][0];
    yyerror("Error size > 4 won't work \n");
    return a;
  }

}

%}

%verbose
//Union type signifying all the types of the tokens which are used in the bison.
%union {
  int num;
  float decimal;
  char* variable_name;
  Value *val;
  rows2d* rows2dptr;
  rows* rowsptr;
  struct var_or_mat *vm;
}

%define parse.trace

%token ERROR

%token RETURN
%token DET
%token TRANSPOSE INVERT
%token REDUCE
%token MATRIX
%token X

%token <decimal> FLOAT
%token <num> INT
%token <variable_name> ID

%token SEMI COMMA

%token PLUS MINUS MUL DIV
%token ASSIGN

%token LBRACKET RBRACKET
%token LPAREN RPAREN
%token LBRACE RBRACE

%type params_list
%type <vm> expr

%type <rowsptr> expr_list
%type <rows2dptr> matrix_rows
%type <rowsptr> matrix_row
%type dim

%left PLUS MINUS
%left MUL DIV

%start program

%%
//Grammar rule for taking the function name of the code.
program: ID {
  // FIXME: set name of function, this is okay, no need to change
  funName = "main"; // FIXME: should not be main!
  funName = $1;
} LPAREN params_list_opt RPAREN LBRACE statements_opt return RBRACE //Grammar rule for taking the arguments, statements and return value (entire program).
{
  // parsing is done, input is accepted
  YYACCEPT;
}
;
//Takes the argument lists of the function.
//FIXME: some changes needed below
params_list_opt:  params_list
{
  // FIXME: This action needs attention!
  // FIXME: this is hard-coded to be a single parameter:
  std::vector<Type*> param_types(args_vec.size(),Builder.getFloatTy());
  ArrayRef<Type*> Params (param_types);

  // Create int function type with no arguments
  FunctionType *FunType =
    FunctionType::get(Builder.getFloatTy(),Params,false);

  // Create a main function
  Function *Function = Function::Create(FunType,GlobalValue::ExternalLinkage,funName,M);

  int arg_no=0;
  //Maps the argument name to the values and stores them in the Variable_mapping vector for future use.
  for(auto &a: Function->args()) {
    //
    // FIXME: match arguments to name in parameter list
    // iterate over arguments of function
    //

    Variable_mappings[args_vec[arg_no]] = &a;

    std::cout<<"Bison params_list MAIN:"<<args_vec[arg_no]<<"\n";
    arg_no++;
  }

  //Add a basic block to main to hold instructions, and set Builder
  //to insert there
  Builder.SetInsertPoint(BasicBlock::Create(TheContext, "entry", Function));
}
| %empty
{
  // Create int function type with no arguments
  FunctionType *FunType =
    FunctionType::get(Builder.getFloatTy(),false);

  // Create a main function
  Function *Function = Function::Create(FunType,
         GlobalValue::ExternalLinkage,funName,M);

  //Add a basic block to main to hold instructions, and set Builder
  //to insert there
  Builder.SetInsertPoint(BasicBlock::Create(TheContext, "entry", Function));
}
;
//Grammar rule for getting the arguments of the function.
params_list: ID
{
  // FIXME: remember ID
  args_vec.push_back($1);
  std::cout<<args_vec[0]<<"\n";

}
| params_list COMMA ID 
{
  // FIXME: remember ID
  args_vec.push_back($3);
}
;
//Grammar rule for performing return expression. It takes only float values and performs return.
return: RETURN expr SEMI
{
  if($2->is_var && $2->value != NULL)
    Builder.CreateRet($2->value);
  else
  {
    yyerror("Return Value should be a varaible not a matrix or null type");
    YYABORT;
  }
  
}
;

// These may be fine without changes
statements_opt: %empty
            | statements
;

// These may be fine without changes
statements:   statement
            | statements statement
;

// Grammar rule for a = 2; Assginment of variable or immendiate or matrix type to another corresponding type.
statement:
ID ASSIGN expr SEMI
{
  if($3->is_var)
  {
    Variable_mappings[$1] = $3->value;
    mat_or_val[$1] = false;
  
  }
  else
  {
    matrices[$1] = matrices[$3->mat_name];
    mat_or_val[$1] = true;
  }
}
//Grammar rule for a = m1 [2x2] {[1,0],[0,1]}; Assignment of matrix.
//Stores the matrix in the map with the matrix name and corresponding 2d vector.
| ID ASSIGN MATRIX dim LBRACE matrix_rows RBRACE SEMI
{
  std::vector<std::vector<Value*> > temp;
  for(const auto r: *$6)
  {
    std::vector<Value*> temp_row;
    for(const auto element: *r)
    {
      temp_row.push_back(element);
    }
    temp.push_back(temp_row);
  }
  matrices[$1] = temp;
  mat_or_val[$1] = true;
}
;

// Grammar rule for [2x2], setting the dimension of the matrix;
dim: LBRACKET INT X INT RBRACKET
{
  dimensions[0] = $2;
  dimensions[1] = $4;
}
;

//Grammar rule for getting the matrix rows. [[2,3],[4,5]]
//Returns a pointer to rows2d type to upper level.
matrix_rows: matrix_row
{
  rows2d *rptr = new rows2d();
  rptr->push_back($1);
  $$ = rptr;
}
| matrix_rows COMMA matrix_row
{
  $$->push_back($3);
}
;

//Grammar rule for a single row entity [2,3]
//Returns a pointer to rows type to upper level.
matrix_row: LBRACKET expr_list RBRACKET
{
  $$ = $2;
}
;

//Grammar rule for getting the values or immediate to be stored in the matrix.
//Returns a pointer to rows type to upper level.
expr_list: expr
{
  if($1->is_var)
    $$ = new rows({$1->value});
}
| expr_list COMMA expr
{
  if($3->is_var)
    $$->push_back($3->value);
}
;

//Grammar rule for getting the variable  or matrix name. 
//Returns the value* type (which is thhe value) for variable and std::string type (matrix name) for matrices
// to upper level.
expr: ID
{
  $$ = new struct var_or_mat;
  if(mat_or_val[$1] == false)
  {
    $$->value =  Variable_mappings[$1];
    $$->is_var = true;
  }
  else
  {
    $$->mat_name = $1;
    $$->is_var = false;
  }

}
//Grammar rule for getting the float value. Returns a Value* type (float value) to upper level.
| FLOAT 
{
  float f = $1;
  Type *floatType = Type::getFloatTy(TheContext);
  $$ = new struct var_or_mat;
  $$->value = ConstantFP::get(floatType, f);
  $$->is_var = true;
}
//Grammar rule for getting the int value. Returns a Value* type (int value) to upper level.
| INT 
{
  Value* temp_val = Builder.CreateUIToFP(Builder.getInt32($1),Builder.getFloatTy());
  $$ = new struct var_or_mat;
  $$->value = temp_val;
  $$->is_var = true;
}
//Grammar rule for computing the addition of variable or matrices. Returns a Value* type for variables
// and std::string type matrix name for matrices to upper level.
| expr PLUS expr 
{
  $$ = new struct var_or_mat;
  if($1->is_var && $3->is_var)
  {
      $$->value = Builder.CreateFAdd($1->value,$3->value);
      $$->is_var = true;
  }
  else if($1->is_var==false && $3->is_var==false)
  {
  
    if(matrices[$1->mat_name].size() != matrices[$3->mat_name].size())
    {
      yyerror("Bison Matrix Addition row dimension error\n");  
      YYABORT;
    }
    for(int i=0;i<matrices[$1->mat_name].size();i++)
    {
      if(matrices[$1->mat_name][i].size() != matrices[$3->mat_name][i].size())
      {
        yyerror("Bison Matrix Addition row dimension error\n");
        YYABORT;
      }
    }

    //performing matrix addition
    std::vector<std::vector<Value*>> temp;
    for(int i=0;i<matrices[$1->mat_name].size();i++)
    {
      std::vector<Value*> temp_row;
      for(int j=0;j<matrices[$1->mat_name][i].size();j++)
      {
        temp_row.push_back(Builder.CreateFAdd(matrices[$1->mat_name][i][j] , matrices[$3->mat_name][i][j]));
      }
      temp.push_back(temp_row);
    }
    matrices["temp"] = temp;
    $$->mat_name = "temp";
    $$->is_var = false;
  }
}
//Grammar rule for performing subtraction of 2 variables or matrices. Returns a Value* type for variables 
//or a std::string type of matrix name for matrices to upper level.
| expr MINUS expr
{
  $$ = new struct var_or_mat;
  if($1->is_var && $3->is_var)
  {
    $$->value = Builder.CreateFSub($1->value,$3->value);
    $$->is_var = true;
  }
  else if($1->is_var==false && $3->is_var==false)
  {
    if(matrices[$1->mat_name].size() != matrices[$3->mat_name].size())
    {
      yyerror("Bison Matrix Subtraction row dimension error\n");
      YYABORT;
    }

    std::vector<std::vector<Value*>> temp;
    for(int i=0;i<matrices[$1->mat_name].size();i++)
    {
      std::vector<Value*> temp_row;
      for(int j=0;j<matrices[$1->mat_name][i].size();j++)
      {
        temp_row.push_back(Builder.CreateFSub(matrices[$1->mat_name][i][j] , matrices[$3->mat_name][i][j]));
      }
      temp.push_back(temp_row);
    }
      matrices["temp"] = temp;
      $$->mat_name = "temp";
      $$->is_var = false;
  }
}
//Grammar rule for performing multiplication of 2 variables or matrices or a matrix and variable. Returns a Value* type for variables 
//or a std::string type of matrix name for matrices to upper level.  
| expr MUL expr
{
  $$ = new struct var_or_mat;
  if($1->is_var && $3->is_var)
  {
    $$->value = Builder.CreateFMul($1->value,$3->value);
    $$->is_var = true;
  }
  else if(!$1->is_var && !$3->is_var)
  {
    std::string name = matrix_product($1->mat_name,$3->mat_name);
    if(name == "error")
      YYABORT;
    $$->is_var = false;
    $$->mat_name = name;
  }
  else if(!$1->is_var && $3->is_var)
  {
    std::vector<std::vector<Value*> > mat = matrices[$1->mat_name];
    Value* mul = $3->value;
    
    for(int i=0;i<mat.size();i++)
    {
      for(int j=0;j<mat[i].size();j++)
      {
        mat[i][j] = Builder.CreateFMul(matrices[$1->mat_name][i][j],mul);  
      }
    }
    
    matrices["temp"] = mat;
    $$->is_var = false;
    $$->mat_name = "temp";
  }
  else if($1->is_var && !$3->is_var)
  {
    std::vector<std::vector<Value*> > mat = matrices[$3->mat_name];
    Value* mul = $1->value;
    
    for(int i=0;i<mat.size();i++)
    {
      for(int j=0;j<mat[i].size();j++)
      {
        mat[i][j] = Builder.CreateFMul(matrices[$1->mat_name][i][j],mul);  
      }
    }
    
    matrices["temp"] = mat;
    $$->is_var = false;
    $$->mat_name = "temp";
  }
    
}
//Grammar rule for performing division of 2 variables or matrices or matrix and variable. Returns a Value* type for variables 
//or a std::string type of matrix name for matrices to upper level.
| expr DIV expr
{
  $$ = new struct var_or_mat;
  if($1->is_var && $3->is_var)
  {
    $$->value = Builder.CreateFDiv($1->value,$3->value);
    $$->is_var = true;
  }
  else if(!$1->is_var && $3->is_var)
  {
    std::vector<std::vector<Value*> > mat = matrices[$1->mat_name];
    Value* div = $3->value;
    
    for(int i=0;i<mat.size();i++)
    {
      for(int j=0;j<mat[i].size();j++)
      {
      
        mat[i][j] = Builder.CreateFDiv(matrices[$1->mat_name][i][j],div);
          
      }
    }
    
    matrices["temp"] = mat;
    $$->is_var = false;
    $$->mat_name = "temp";
  }
  else if(!$1->is_var && !$3->is_var)  
  {
    //Matrix division for 2x2, 3x3 and 4x4
    std::vector<std::vector<Value*> > mat1 = matrices[$1->mat_name];
    std::vector<std::vector<Value*> > mat2 = matrices[$3->mat_name];

    //Inverse of second matrix
    if(mat2.size() == 2)
    {
      Value *det = find_determinant($3->mat_name);
      mat2[0][0] = Builder.CreateFDiv(matrices[$3->mat_name][1][1],det);
      mat2[0][1] = Builder.CreateFDiv(Builder.CreateFNeg(matrices[$3->mat_name][0][1]),det);
      mat2[1][0] = Builder.CreateFDiv(Builder.CreateFNeg(matrices[$3->mat_name][1][0]),det);
      mat2[1][1] = Builder.CreateFDiv(matrices[$3->mat_name][0][0],det);
    }
    else if(mat2.size() == 3)
    {
      Value *det = find_determinant($3->mat_name);
      Value* one = ConstantFP::get(Type::getFloatTy(TheContext), 1.0);
      Value *inv_det = Builder.CreateFDiv(one,det);
      mat2[0][0] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][1],matrices[$3->mat_name][2][2]),Builder.CreateFMul(matrices[$3->mat_name][2][1],matrices[$3->mat_name][1][2])));
      mat2[0][1] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][2],matrices[$3->mat_name][2][1]),Builder.CreateFMul(matrices[$3->mat_name][0][1],matrices[$3->mat_name][2][2])));
      mat2[0][2] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][1],matrices[$3->mat_name][1][2]),Builder.CreateFMul(matrices[$3->mat_name][0][2],matrices[$3->mat_name][1][1])));

      mat2[1][0] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][2],matrices[$3->mat_name][2][0]),Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][2][2])));
      mat2[1][1] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][2][2]),Builder.CreateFMul(matrices[$3->mat_name][0][2],matrices[$3->mat_name][2][0])));
      mat2[1][2] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][0][2]),Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][1][2])));

      mat2[2][0] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][2][1]),Builder.CreateFMul(matrices[$3->mat_name][2][0],matrices[$3->mat_name][1][1])));
      mat2[2][1] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][2][0],matrices[$3->mat_name][0][1]),Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][2][1])));
      mat2[2][2] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][1][1]),Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][0][1])));
    }
    else if(mat2.size() == 4)
    {
      //Algorithm referenced from stackoverflow https://stackoverflow.com/questions/1148309/inverting-a-4x4-matrix?rq=1
      Value* m00 = matrices[$3->mat_name][0][0];
      Value* m01 = matrices[$3->mat_name][0][1];
      Value* m02 = matrices[$3->mat_name][0][2];
      Value* m03 = matrices[$3->mat_name][0][3];

      Value* m10 = matrices[$3->mat_name][1][0];
      Value* m11 = matrices[$3->mat_name][1][1];
      Value* m12 = matrices[$3->mat_name][1][2];
      Value* m13 = matrices[$3->mat_name][1][3];

      Value* m20 = matrices[$3->mat_name][2][0];
      Value* m21 = matrices[$3->mat_name][2][1];
      Value* m22 = matrices[$3->mat_name][2][2];
      Value* m23 = matrices[$3->mat_name][2][3];

      Value* m30 = matrices[$3->mat_name][3][0];
      Value* m31 = matrices[$3->mat_name][3][1];
      Value* m32 = matrices[$3->mat_name][3][2];
      Value* m33 = matrices[$3->mat_name][3][3];

      Value* A2323 = Builder.CreateFSub(Builder.CreateFMul(m22,m33),Builder.CreateFMul(m23,m32));
      Value* A1323 = Builder.CreateFSub(Builder.CreateFMul(m21,m33),Builder.CreateFMul(m23,m31));
      Value* A1223 = Builder.CreateFSub(Builder.CreateFMul(m21,m32),Builder.CreateFMul(m22,m31));
      Value* A0323 = Builder.CreateFSub(Builder.CreateFMul(m20,m33),Builder.CreateFMul(m23,m30));
      Value* A0223 = Builder.CreateFSub(Builder.CreateFMul(m20,m32),Builder.CreateFMul(m22,m30));
      Value* A0123 = Builder.CreateFSub(Builder.CreateFMul(m20,m31),Builder.CreateFMul(m21,m30));
      Value* A2313 = Builder.CreateFSub(Builder.CreateFMul(m12,m33),Builder.CreateFMul(m13,m32));
      Value* A1313 = Builder.CreateFSub(Builder.CreateFMul(m11,m33),Builder.CreateFMul(m13,m31));
      Value* A1213 = Builder.CreateFSub(Builder.CreateFMul(m11,m32),Builder.CreateFMul(m12,m31));
      Value* A2312 = Builder.CreateFSub(Builder.CreateFMul(m12,m23),Builder.CreateFMul(m13,m22));
      Value* A1312 = Builder.CreateFSub(Builder.CreateFMul(m11,m23),Builder.CreateFMul(m13,m21));
      Value* A1212 = Builder.CreateFSub(Builder.CreateFMul(m11,m22),Builder.CreateFMul(m12,m21));
      Value* A0313 = Builder.CreateFSub(Builder.CreateFMul(m10,m33),Builder.CreateFMul(m13,m30));
      Value* A0213 = Builder.CreateFSub(Builder.CreateFMul(m10,m32),Builder.CreateFMul(m12,m30));
      Value* A0312 = Builder.CreateFSub(Builder.CreateFMul(m10,m23),Builder.CreateFMul(m13,m20));
      Value* A0212 = Builder.CreateFSub(Builder.CreateFMul(m10,m22),Builder.CreateFMul(m12,m20));
      Value* A0113 = Builder.CreateFSub(Builder.CreateFMul(m10,m31),Builder.CreateFMul(m11,m30));
      Value* A0112 = Builder.CreateFSub(Builder.CreateFMul(m10,m21),Builder.CreateFMul(m11,m20));

      Value *det = find_determinant($3->mat_name);
      Value* one = ConstantFP::get(Type::getFloatTy(TheContext), 1.0);
      Value *inv_det = Builder.CreateFDiv(one,det);

      mat2[0][0] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m11 , A2323) , Builder.CreateFMul(m12 , A1323)) , Builder.CreateFMul(m13 , A1223)));
      mat2[0][1] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m01 , A2323) , Builder.CreateFMul(m02 , A1323)) , Builder.CreateFMul(m03 , A1223))));
      mat2[0][2] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m01 , A2313) , Builder.CreateFMul(m02 , A1313)) , Builder.CreateFMul(m03 , A1213)));
      mat2[0][3] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m01 , A2312) , Builder.CreateFMul(m02 , A1312)) , Builder.CreateFMul(m03 , A1212))));
      mat2[1][0] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m10 , A2323) , Builder.CreateFMul(m12 , A0323)) , Builder.CreateFMul(m13 , A0223))));
      mat2[1][1] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A2323) , Builder.CreateFMul(m02 , A0323)) , Builder.CreateFMul(m03 , A0223)));
      mat2[1][2] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A2313) , Builder.CreateFMul(m02 , A0313)) , Builder.CreateFMul(m03 , A0213))));
      mat2[1][3] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A2312) , Builder.CreateFMul(m02 , A0312)) , Builder.CreateFMul(m03 , A0212)));
      mat2[2][0] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m10 , A1323) , Builder.CreateFMul(m11 , A0323)) , Builder.CreateFMul(m13 , A0123)));
      mat2[2][1] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1323) , Builder.CreateFMul(m01 , A0323)) , Builder.CreateFMul(m03 , A0123))));
      mat2[2][2] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1313) , Builder.CreateFMul(m01 , A0313)) , Builder.CreateFMul(m03 , A0113)));
      mat2[2][3] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1312) , Builder.CreateFMul(m01 , A0312)) , Builder.CreateFMul(m03 , A0112))));
      mat2[3][0] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m10 , A1223) , Builder.CreateFMul(m11 , A0223)) , Builder.CreateFMul(m12 , A0123))));
      mat2[3][1] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1223) , Builder.CreateFMul(m01 , A0223)) , Builder.CreateFMul(m02 , A0123)));
      mat2[3][2] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1213) , Builder.CreateFMul(m01 , A0213)) , Builder.CreateFMul(m02 , A0113))));
      mat2[3][3] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1212) , Builder.CreateFMul(m01 , A0212)) , Builder.CreateFMul(m02 , A0112)));
    }
    else
    {
      yyerror("Size of matrix is more than 4, requires size to be less than or equal to 4\n");
      YYABORT;
    }

    //Finding product
    matrices["inverted"] = mat2;
    std::string name = matrix_product($1->mat_name,"inverted");
    if(name == "error")
      YYABORT;
    $$->is_var = false;
    $$->mat_name = name;

  }
}
//Grammar rule for performing negation of 2 variables or matrices. Returns a Value* type for variables 
//or a std::string type of matrix name for matrices to upper level.
| MINUS expr
{
  $$ = new struct var_or_mat;
  if($2->is_var)
  {
    $$->value = Builder.CreateFNeg($2->value);
    $$->is_var = true;
  }
  else
  {
    std::vector<std::vector<Value*> > mat = matrices[$2->mat_name];
    for(int i=0;i<mat.size();i++)
    {
      for(int j=0;j<mat[i].size();j++)
      {
        mat[i][j] = Builder.CreateFNeg(mat[i][j]);
      }
    }
    matrices["temp"] = mat;
    $$->is_var = false;
    $$->mat_name = "temp";
  }
}
//Grammar rule for performing the determinant operation of a matrix. Returns a Value* type (float value)
//to upper level.
| DET LPAREN expr RPAREN
{
  $$ = new struct var_or_mat;
  if(matrices[$3->mat_name].size() != matrices[$3->mat_name][0].size())
  {
    yyerror("Determinant can't be taken for non square matrix");
    YYABORT;
  }
  $$->value = find_determinant($3->mat_name);
  $$->is_var = true;
}
//Grammar rule for finding the inverse of a matrix. Returns a std::string type (matrix name) of the resultant
//matrix to upper level.
| INVERT LPAREN expr RPAREN
{
  //Algorithm referred from stackoverflow: https://stackoverflow.com/questions/983999/simple-3x3-matrix-inverse-code-c
  $$ = new struct var_or_mat;
  std::vector<std::vector<Value*> > mat = matrices[$3->mat_name];
  if(mat.size() == 2)
  {
    Value *det = find_determinant($3->mat_name);
    mat[0][0] = Builder.CreateFDiv(matrices[$3->mat_name][1][1],det);
    mat[0][1] = Builder.CreateFDiv(Builder.CreateFNeg(matrices[$3->mat_name][0][1]),det);
    mat[1][0] = Builder.CreateFDiv(Builder.CreateFNeg(matrices[$3->mat_name][1][0]),det);
    mat[1][1] = Builder.CreateFDiv(matrices[$3->mat_name][0][0],det);

    matrices["temp"] =  mat;
    $$->is_var = false;
    $$->mat_name = "temp";
  }
  else if(mat.size() == 3)
  {
    Value *det = find_determinant($3->mat_name);
    Value* one = ConstantFP::get(Type::getFloatTy(TheContext), 1.0);
    Value *inv_det = Builder.CreateFDiv(one,det);
    mat[0][0] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][1],matrices[$3->mat_name][2][2]),Builder.CreateFMul(matrices[$3->mat_name][2][1],matrices[$3->mat_name][1][2])));
    mat[0][1] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][2],matrices[$3->mat_name][2][1]),Builder.CreateFMul(matrices[$3->mat_name][0][1],matrices[$3->mat_name][2][2])));
    mat[0][2] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][1],matrices[$3->mat_name][1][2]),Builder.CreateFMul(matrices[$3->mat_name][0][2],matrices[$3->mat_name][1][1])));

    mat[1][0] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][2],matrices[$3->mat_name][2][0]),Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][2][2])));
    mat[1][1] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][2][2]),Builder.CreateFMul(matrices[$3->mat_name][0][2],matrices[$3->mat_name][2][0])));
    mat[1][2] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][0][2]),Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][1][2])));

    mat[2][0] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][2][1]),Builder.CreateFMul(matrices[$3->mat_name][2][0],matrices[$3->mat_name][1][1])));
    mat[2][1] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][2][0],matrices[$3->mat_name][0][1]),Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][2][1])));
    mat[2][2] = Builder.CreateFMul(inv_det,Builder.CreateFSub(Builder.CreateFMul(matrices[$3->mat_name][0][0],matrices[$3->mat_name][1][1]),Builder.CreateFMul(matrices[$3->mat_name][1][0],matrices[$3->mat_name][0][1])));

    matrices["temp"] =  mat;
    $$->is_var = false;
    $$->mat_name = "temp";
  }
  else if(mat.size() == 4)
  {
    //Algorithm referenced from stackoverflow https://stackoverflow.com/questions/1148309/inverting-a-4x4-matrix?rq=1
    std::vector<std::vector<Value*> > mat = matrices[$3->mat_name];
    Value* m00 = matrices[$3->mat_name][0][0];
    Value* m01 = matrices[$3->mat_name][0][1];
    Value* m02 = matrices[$3->mat_name][0][2];
    Value* m03 = matrices[$3->mat_name][0][3];

    Value* m10 = matrices[$3->mat_name][1][0];
    Value* m11 = matrices[$3->mat_name][1][1];
    Value* m12 = matrices[$3->mat_name][1][2];
    Value* m13 = matrices[$3->mat_name][1][3];

    Value* m20 = matrices[$3->mat_name][2][0];
    Value* m21 = matrices[$3->mat_name][2][1];
    Value* m22 = matrices[$3->mat_name][2][2];
    Value* m23 = matrices[$3->mat_name][2][3];

    Value* m30 = matrices[$3->mat_name][3][0];
    Value* m31 = matrices[$3->mat_name][3][1];
    Value* m32 = matrices[$3->mat_name][3][2];
    Value* m33 = matrices[$3->mat_name][3][3];

    Value* A2323 = Builder.CreateFSub(Builder.CreateFMul(m22,m33),Builder.CreateFMul(m23,m32));
    Value* A1323 = Builder.CreateFSub(Builder.CreateFMul(m21,m33),Builder.CreateFMul(m23,m31));
    Value* A1223 = Builder.CreateFSub(Builder.CreateFMul(m21,m32),Builder.CreateFMul(m22,m31));
    Value* A0323 = Builder.CreateFSub(Builder.CreateFMul(m20,m33),Builder.CreateFMul(m23,m30));
    Value* A0223 = Builder.CreateFSub(Builder.CreateFMul(m20,m32),Builder.CreateFMul(m22,m30));
    Value* A0123 = Builder.CreateFSub(Builder.CreateFMul(m20,m31),Builder.CreateFMul(m21,m30));
    Value* A2313 = Builder.CreateFSub(Builder.CreateFMul(m12,m33),Builder.CreateFMul(m13,m32));
    Value* A1313 = Builder.CreateFSub(Builder.CreateFMul(m11,m33),Builder.CreateFMul(m13,m31));
    Value* A1213 = Builder.CreateFSub(Builder.CreateFMul(m11,m32),Builder.CreateFMul(m12,m31));
    Value* A2312 = Builder.CreateFSub(Builder.CreateFMul(m12,m23),Builder.CreateFMul(m13,m22));
    Value* A1312 = Builder.CreateFSub(Builder.CreateFMul(m11,m23),Builder.CreateFMul(m13,m21));
    Value* A1212 = Builder.CreateFSub(Builder.CreateFMul(m11,m22),Builder.CreateFMul(m12,m21));
    Value* A0313 = Builder.CreateFSub(Builder.CreateFMul(m10,m33),Builder.CreateFMul(m13,m30));
    Value* A0213 = Builder.CreateFSub(Builder.CreateFMul(m10,m32),Builder.CreateFMul(m12,m30));
    Value* A0312 = Builder.CreateFSub(Builder.CreateFMul(m10,m23),Builder.CreateFMul(m13,m20));
    Value* A0212 = Builder.CreateFSub(Builder.CreateFMul(m10,m22),Builder.CreateFMul(m12,m20));
    Value* A0113 = Builder.CreateFSub(Builder.CreateFMul(m10,m31),Builder.CreateFMul(m11,m30));
    Value* A0112 = Builder.CreateFSub(Builder.CreateFMul(m10,m21),Builder.CreateFMul(m11,m20));

    Value *det = find_determinant($3->mat_name);
    Value* one = ConstantFP::get(Type::getFloatTy(TheContext), 1.0);
    Value *inv_det = Builder.CreateFDiv(one,det);

    mat[0][0] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m11 , A2323) , Builder.CreateFMul(m12 , A1323)) , Builder.CreateFMul(m13 , A1223)));
    mat[0][1] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m01 , A2323) , Builder.CreateFMul(m02 , A1323)) , Builder.CreateFMul(m03 , A1223))));
    mat[0][2] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m01 , A2313) , Builder.CreateFMul(m02 , A1313)) , Builder.CreateFMul(m03 , A1213)));
    mat[0][3] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m01 , A2312) , Builder.CreateFMul(m02 , A1312)) , Builder.CreateFMul(m03 , A1212))));
    mat[1][0] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m10 , A2323) , Builder.CreateFMul(m12 , A0323)) , Builder.CreateFMul(m13 , A0223))));
    mat[1][1] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A2323) , Builder.CreateFMul(m02 , A0323)) , Builder.CreateFMul(m03 , A0223)));
    mat[1][2] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A2313) , Builder.CreateFMul(m02 , A0313)) , Builder.CreateFMul(m03 , A0213))));
    mat[1][3] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A2312) , Builder.CreateFMul(m02 , A0312)) , Builder.CreateFMul(m03 , A0212)));
    mat[2][0] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m10 , A1323) , Builder.CreateFMul(m11 , A0323)) , Builder.CreateFMul(m13 , A0123)));
    mat[2][1] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1323) , Builder.CreateFMul(m01 , A0323)) , Builder.CreateFMul(m03 , A0123))));
    mat[2][2] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1313) , Builder.CreateFMul(m01 , A0313)) , Builder.CreateFMul(m03 , A0113)));
    mat[2][3] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1312) , Builder.CreateFMul(m01 , A0312)) , Builder.CreateFMul(m03 , A0112))));
    mat[3][0] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m10 , A1223) , Builder.CreateFMul(m11 , A0223)) , Builder.CreateFMul(m12 , A0123))));
    mat[3][1] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1223) , Builder.CreateFMul(m01 , A0223)) , Builder.CreateFMul(m02 , A0123)));
    mat[3][2] = Builder.CreateFMul(inv_det ,Builder.CreateFNeg(Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1213) , Builder.CreateFMul(m01 , A0213)) , Builder.CreateFMul(m02 , A0113))));
    mat[3][3] = Builder.CreateFMul(inv_det ,Builder.CreateFAdd(Builder.CreateFSub(Builder.CreateFMul(m00 , A1212) , Builder.CreateFMul(m01 , A0212)) , Builder.CreateFMul(m02 , A0112)));

    matrices["temp"] =  mat;
    $$->is_var = false;
    $$->mat_name = "temp";

  }
  else
  {
    yyerror("Size of matrix is more than 4, requires size to be less than or equal to 4\n");
    YYABORT;
  }
}
//Grammar rule for performing the transpose operation of a matrix. Returns a std::string type (matrix name) of the resultant
//matrix to upper level.
| TRANSPOSE LPAREN expr RPAREN
{
  $$ = new struct var_or_mat;
  std::vector<std::vector<Value*> > a = matrices[$3->mat_name];
  for(int i=0;i<a[0].size();i++)
  {
    for(int j=0;j<a.size();j++)
    {
      a[i][j] = matrices[$3->mat_name][j][i];
    }
  }

  matrices["temp"] = a;
  $$->is_var = false;
  $$->mat_name = "temp";
}
//Grammar rule for getting a single value from a matrix. Return a Value* type (float value) to upper level.
| ID LBRACKET INT COMMA INT RBRACKET
{
  $$ = new struct var_or_mat;
  int row = $3;
  int col = $5;
  $$->value = matrices[$1][row][col];
  $$->is_var = true;
}
//Grammar rule for performing reduction operation of a matrix. Returns a std::string type (matrix name) of the resultant
//matrix to upper level.
| REDUCE LPAREN expr RPAREN
{
  $$ = new struct var_or_mat;
  $$->value = reduction($3->mat_name);
  $$->is_var = true;
}
//Grammar rule for providing precedence of an expression using a variable or matrix. Returns a Value* or 
//std::string (float type) to upper level.
| LPAREN expr RPAREN 
{
  $$ = new struct var_or_mat;
  $$ = $2;
}
;


%%

unique_ptr<Module> parseP1File(const string &InputFilename)
{
  string modName = InputFilename;
  if (modName.find_last_of('/') != string::npos)
    modName = modName.substr(modName.find_last_of('/')+1);
  if (modName.find_last_of('.') != string::npos)
    modName.resize(modName.find_last_of('.'));

  // unique_ptr will clean up after us, call destructor, etc.
  unique_ptr<Module> Mptr(new Module(modName.c_str(), TheContext));

  // set global module
  M = Mptr.get();
  
  /* this is the name of the file to generate, you can also use
     this string to figure out the name of the generated function */

  if (InputFilename == "--")
    yyin = stdin;
  else	  
    yyin = fopen(InputFilename.c_str(),"r");

  yydebug = 1;
  if (yyparse() != 0) {
    // Dump LLVM IR to the screen for debugging
    M->print(errs(),nullptr,false,true);
    // errors, so discard module
    Mptr.reset();
  } else {
    // Dump LLVM IR to the screen for debugging
    M->print(errs(),nullptr,false,true);
  }
  
  return Mptr;
}

void yyerror(const char* msg)
{
  printf("%s\n",msg);
}
