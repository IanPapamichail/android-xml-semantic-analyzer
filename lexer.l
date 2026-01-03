%{
#include "parser.tab.h"
#include <string.h>
#include <stdlib.h>

int line = 1;
%}

%%

"</"        {printf("TOKEN: END_LT\n"); return END_LT; }
"/>"        {printf("TOKEN: SLASH_GT\n"); return SLASH_GT; }
"<"         {printf("TOKEN: LT\n"); return LT; }
">"         {printf("TOKEN: GT\n"); return GT; }
"="         {printf("TOKEN: EQ\n"); return EQ; }

\"[^\n"]*\" {
    printf("TOKEN: STRING(%s)\n", yytext);
    yylval.str = strdup(yytext);
    return STRING;
}

[A-Za-z_:][A-Za-z0-9_:]* {
    printf("TOKEN: NAME(%s)\n", yytext);
    yylval.str = strdup(yytext);
    return NAME;
}

[ \t\r]+    ;
\n          { line++; }

. {
    printf("LEXICAL ERROR: unexpected character '%s' at line %d\n", yytext, line);
    exit(1);
}

%%

int yywrap(void) {
    return 1;
}
