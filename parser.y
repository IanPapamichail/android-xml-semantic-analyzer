%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------- android:id uniqueness ---------- */
#define MAX_IDS 1000
char ids[MAX_IDS][100];
int id_count = 0;

int id_exists(const char *id) {
    for (int i = 0; i < id_count; i++)
        if (strcmp(ids[i], id) == 0) return 1;
    return 0;
}

/* ---------- progress / max ---------- */
int current_max = -1;
int current_progress = -1;

/* ---------- RadioGroup / RadioButton ---------- */
int inside_radiogroup = 0;
char checked_button[100] = "";
char radiobutton_ids[100][100];
int radiobutton_count = 0;
int declared_radio_count = -1;

/* ---------- lexer interface ---------- */
extern int yylex(void);
extern int line;
void yyerror(const char *s);
%}

%union {
    char *str;
}

%token <str> NAME STRING
%token LT GT SLASH_GT END_LT EQ
%start program

%%

/* ================= PROGRAM ================= */
program:
    elements
    {
        printf("VALID XML\n");
    }
;

/* ================= ELEMENTS ================= */
elements:
      element
    | elements element
;

/* ================= ELEMENT ================= */
element:
      start_tag content end_tag
      {
          /* progress <= max */
          if (current_max != -1 && current_progress != -1 &&
              current_progress > current_max) {
              printf(
                  "Semantic error: android:progress (%d) > android:max (%d) at line %d\n",
                  current_progress, current_max, line
              );
              exit(1);
          }

          current_max = -1;
          current_progress = -1;

          /* RadioGroup checks */
          if (inside_radiogroup) {

              /* checkedButton must exist */
              if (checked_button[0] != '\0') {
                  int found = 0;
                  for (int i = 0; i < radiobutton_count; i++) {
                      if (strcmp(radiobutton_ids[i], checked_button) == 0) {
                          found = 1;
                          break;
                      }
                  }
                  if (!found) {
                      printf(
                          "Semantic error: checkedButton '%s' not found in RadioGroup at line %d\n",
                          checked_button, line
                      );
                      exit(1);
                  }
              }

              /* Question 3: count check */
              if (declared_radio_count != -1 &&
                  declared_radio_count != radiobutton_count) {
                  printf(
                      "Semantic error: android:count=%d but found %d RadioButton(s) at line %d\n",
                      declared_radio_count, radiobutton_count, line
                  );
                  exit(1);
              }

              inside_radiogroup = 0;
              radiobutton_count = 0;
              declared_radio_count = -1;
              checked_button[0] = '\0';
          }
      }

    | LT NAME attributes SLASH_GT
      {
          /* self-closing element */

          if (inside_radiogroup && strcmp($2, "RadioButton") == 0) {
              radiobutton_count++;
          }

          if (current_max != -1 && current_progress != -1 &&
              current_progress > current_max) {
              printf(
                  "Semantic error: android:progress (%d) > android:max (%d) at line %d\n",
                  current_progress, current_max, line
              );
              exit(1);
          }

          current_max = -1;
          current_progress = -1;
      }
;

/* ================= START TAG ================= */
start_tag:
    LT NAME attributes GT
    {
        if (strcmp($2, "RadioGroup") == 0) {
            inside_radiogroup = 1;
            radiobutton_count = 0;
            declared_radio_count = -1;
            checked_button[0] = '\0';
        }
    }
;

/* ================= END TAG ================= */
end_tag:
    END_LT NAME GT
;

/* ================= ATTRIBUTES ================= */
attributes:
      /* empty */
    | attributes NAME EQ STRING
      {
          /* 2α: unique android:id */
          if (strcmp($2, "android:id") == 0) {
              char id[100];
              if (sscanf($4, "\"@+id/%99[^\"]\"", id) == 1) {
                  if (id_exists(id)) {
                      printf(
                          "Semantic error: duplicate android:id '%s' at line %d\n",
                          id, line
                      );
                      exit(1);
                  }
                  strcpy(ids[id_count++], id);

                  if (inside_radiogroup)
                      strcpy(radiobutton_ids[radiobutton_count++], id);
              }
          }

          /* 2β: layout_width / layout_height */
          if (strcmp($2, "android:layout_width") == 0 ||
              strcmp($2, "android:layout_height") == 0) {

              int v;
              if (strcmp($4, "\"wrap_content\"") == 0 ||
                  strcmp($4, "\"match_parent\"") == 0) {
                  /* ok */
              }
              else if (sscanf($4, "\"%d\"", &v) == 1 && v > 0) {
                  /* ok */
              }
              else {
                  printf(
                      "Semantic error: %s has invalid value %s at line %d\n",
                      $2, $4, line
                  );
                  exit(1);
              }
          }

          /* 2γ: padding > 0 */
          if (strcmp($2, "android:padding") == 0) {
              int p;
              if (sscanf($4, "\"%d\"", &p) == 1 && p <= 0) {
                  printf(
                      "Semantic error: android:padding must be > 0 at line %d\n",
                      line
                  );
                  exit(1);
              }
          }

          /* progress >= 0 */
          if (strcmp($2, "android:progress") == 0) {
              sscanf($4, "\"%d\"", &current_progress);
              if (current_progress < 0) {
                  printf(
                      "Semantic error: android:progress must be >= 0 at line %d\n",
                      line
                  );
                  exit(1);
              }
          }

          if (strcmp($2, "android:max") == 0)
              sscanf($4, "\"%d\"", &current_max);

          /* RadioGroup attributes */
          if (inside_radiogroup && strcmp($2, "android:checkedButton") == 0)
              sscanf($4, "\"@+id/%99[^\"]\"", checked_button);

          /* Question 3: android:count */
          if (inside_radiogroup && strcmp($2, "android:count") == 0) {
              sscanf($4, "\"%d\"", &declared_radio_count);
              if (declared_radio_count <= 0) {
                  printf(
                      "Semantic error: android:count must be > 0 at line %d\n",
                      line
                  );
                  exit(1);
              }
          }
      }
;

/* ================= CONTENT ================= */
content:
      /* empty */
    | elements
;

%%

void yyerror(const char *s) {
    printf("Syntax error at line %d\n", line);
}

int main(void) {
    return yyparse();
}
