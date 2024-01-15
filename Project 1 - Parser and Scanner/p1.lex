%{
#include <stdio.h>
#include <math.h>
#include <cstdio>
#include <list>
#include <iostream>
#include <string>
#include <memory>
#include <stdexcept>

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Value.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Type.h"
#include "llvm/IR/IRBuilder.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Support/SystemUtils.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/FileSystem.h"

using namespace std;
using namespace llvm;  

typedef std::vector<std::vector<Value*>*> rows2d;
typedef std::vector<Value*> rows;

#include "p1.y.hpp"
%}

%option debug

%%

[ \t\n]         //ignore

return       { printf("Return statement\n"); return RETURN; }
det          { printf("DET \n"); return DET; }
transpose    { printf("TRANSPOSE \n");return TRANSPOSE; }
invert       { printf("INVERT \n"); return INVERT; }
matrix       { printf("MATRIX\n"); return MATRIX; }
reduce       { printf("REDUCE \n"); return REDUCE; }
x            { return X; }

[a-zA-Z_][a-zA-Z_0-9]* { printf("Variable %s\n",yytext); yylval.variable_name=strdup(yytext); return ID; }

[0-9]+        { printf("INT Immediate %s\n",yytext); yylval.num = atoi(yytext); return INT; }

[0-9]+("."[0-9]*) { printf("FLOAT Immediate %s \n",yytext); yylval.decimal = atof(yytext); return FLOAT; }

"["           { printf("LBRACKET \n"); return LBRACKET; }
"]"           { printf("RBRACKET \n"); return RBRACKET; }
"{"           { printf("LBRACE \n"); return LBRACE; }
"}"           { printf("RBRACE \n"); return RBRACE; }
"("           { printf("LPAREN \n"); return LPAREN; }
")"           { printf("RPAREN \n"); return RPAREN; }

"="           { printf("ASSIGN \n"); return ASSIGN; }
"*"           { printf("MUL \n"); return MUL; }
"/"           { printf("DIV \n"); return DIV; }
"+"           { printf("PLUS \n"); return PLUS; }
"-"           { printf("MINUS \n"); return MINUS; }

","           { printf("COMMA \n"); return COMMA; }

";"           { return SEMI; }


"//".*\n      { }

.             { printf("Anything else %s\n",yytext); return ERROR; }
%%

int yywrap()
{
  return 1;
}
