/*
 * lexer.l — tokenizer for Android layout XML.
 *
 * Skips the XML declaration, processing instructions and comments.
 * An unexpected character is reported and skipped, so scanning continues.
 */

%option noyywrap nounput noinput yylineno

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "parser.tab.h"

#define YY_USER_ACTION yylloc.first_line = yylloc.last_line = yylineno;
#define TRACE(...) do { if (trace_tokens) printf(__VA_ARGS__); } while (0)
%}

%x COMMENT PI

%%

"<!--"              { BEGIN(COMMENT); }
<COMMENT>"-->"      { BEGIN(INITIAL); }
<COMMENT>[^-]+|"-"  ;
<COMMENT><<EOF>>    { diag_error(yylineno, "unterminated comment"); BEGIN(INITIAL); return 0; }

"<?"                { BEGIN(PI); }
<PI>"?>"            { BEGIN(INITIAL); }
<PI>[^?]+|"?"       ;
<PI><<EOF>>         { diag_error(yylineno, "unterminated <? ... ?> declaration"); BEGIN(INITIAL); return 0; }

"</"        { TRACE("TOKEN: END_LT\n");   return END_LT; }
"/>"        { TRACE("TOKEN: SLASH_GT\n"); return SLASH_GT; }
"<"         { TRACE("TOKEN: LT\n");       return LT; }
">"         { TRACE("TOKEN: GT\n");       return GT; }
"="         { TRACE("TOKEN: EQ\n");       return EQ; }

\"[^\n"]*\" {
    TRACE("TOKEN: STRING(%s)\n", yytext);
    yylval.str = strdup(yytext);
    return STRING;
}

[A-Za-z_:][A-Za-z0-9_:.\-]* {
    TRACE("TOKEN: NAME(%s)\n", yytext);
    yylval.str = strdup(yytext);
    return NAME;
}

[ \t\r\n]+  ;

. { diag_error(yylineno, "unexpected character '%s'", yytext); }

%%
