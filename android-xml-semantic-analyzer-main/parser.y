/*
 * parser.y — grammar and semantic analysis for Android layout XML.
 *
 * Semantic checks run as grammar actions. Every diagnostic goes through
 * diag_error(), which records the error and lets parsing continue, so one
 * run reports every lexical and semantic error in the file.
 */

%code provides {
    void diag_error(int line, const char *fmt, ...);
    extern int trace_tokens;
}

%{
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int yylex(void);
extern FILE *yyin;
void yyerror(const char *s);

/* ---------- diagnostics ---------- */
static const char *input_name = "<stdin>";
static int error_count = 0;
int trace_tokens = 0;

void diag_error(int line, const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "%s:%d: error: ", input_name, line);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    error_count++;
}

/* ---------- allocation helpers ---------- */
static void *xrealloc(void *p, size_t n) {
    void *q = realloc(p, n);
    if (!q) {
        perror("realloc");
        exit(2);
    }
    return q;
}

static char *xstrdup(const char *s) {
    char *d = xrealloc(NULL, strlen(s) + 1);
    strcpy(d, s);
    return d;
}

/* Copy of a quoted lexeme without its surrounding quotes. */
static char *unquote(const char *quoted) {
    size_t n = strlen(quoted) - 2;
    char *s = xrealloc(NULL, n + 1);
    memcpy(s, quoted + 1, n);
    s[n] = '\0';
    return s;
}

/* Leading integer of a value such as "20dp". Fails on no digits or overflow. */
static int leading_int(const char *value, long *out) {
    char *end;
    errno = 0;
    long v = strtol(value, &end, 10);
    if (end == value || errno == ERANGE)
        return 0;
    *out = v;
    return 1;
}

/* Name part of an id reference ("@+id/name" or "@id/name"), or NULL. */
static const char *id_name(const char *value) {
    const char *name = NULL;
    if (strncmp(value, "@+id/", 5) == 0)
        name = value + 5;
    else if (strncmp(value, "@id/", 4) == 0)
        name = value + 4;
    return (name && *name) ? name : NULL;
}

/* ---------- growable list of ids with the line each was declared on ---------- */
typedef struct {
    char **names;
    int *lines;
    size_t len, cap;
} IdList;

static long idlist_find(const IdList *l, const char *name) {
    for (size_t i = 0; i < l->len; i++)
        if (strcmp(l->names[i], name) == 0)
            return (long)i;
    return -1;
}

static void idlist_add(IdList *l, const char *name, int line) {
    if (l->len == l->cap) {
        l->cap = l->cap ? l->cap * 2 : 16;
        l->names = xrealloc(l->names, l->cap * sizeof *l->names);
        l->lines = xrealloc(l->lines, l->cap * sizeof *l->lines);
    }
    l->names[l->len] = xstrdup(name);
    l->lines[l->len] = line;
    l->len++;
}

static void idlist_free(IdList *l) {
    for (size_t i = 0; i < l->len; i++)
        free(l->names[i]);
    free(l->names);
    free(l->lines);
    memset(l, 0, sizeof *l);
}

/* All android:id values declared in the document. */
static IdList declared_ids;

/* ---------- element stack: per-element semantic state ---------- */
typedef struct {
    char *name;
    int line;

    /* android:progress <= android:max */
    int has_max, has_progress;
    long max, progress;

    /* RadioGroup only */
    char *checked_button;
    int checked_line;
    int has_count;
    long declared_count;
    long radio_count;
    IdList radio_ids;
} Frame;

static Frame *stack;
static size_t depth, stack_cap;

static Frame *top(void) { return &stack[depth - 1]; }

static int is_radio_group(const Frame *f) { return strcmp(f->name, "RadioGroup") == 0; }

/* Nearest RadioGroup enclosing the current element, or NULL. */
static Frame *enclosing_radio_group(void) {
    for (size_t i = depth - 1; i-- > 0; )
        if (is_radio_group(&stack[i]))
            return &stack[i];
    return NULL;
}

static void free_frame(Frame *f) {
    free(f->name);
    free(f->checked_button);
    idlist_free(&f->radio_ids);
}

static void open_element(char *name, int line) {
    if (depth == stack_cap) {
        stack_cap = stack_cap ? stack_cap * 2 : 16;
        stack = xrealloc(stack, stack_cap * sizeof *stack);
    }
    Frame *f = &stack[depth++];
    memset(f, 0, sizeof *f);
    f->name = name;
    f->line = line;

    if (strcmp(name, "RadioButton") == 0) {
        Frame *group = enclosing_radio_group();
        if (group)
            group->radio_count++;
    }
}

static void check_attribute(const char *attr, const char *value, int line) {
    Frame *f = top();
    long n;

    if (strcmp(attr, "android:id") == 0) {
        const char *id = id_name(value);
        if (!id) {
            diag_error(line, "android:id must be \"@+id/name\", got \"%s\"", value);
            return;
        }
        long prev = idlist_find(&declared_ids, id);
        if (prev >= 0)
            diag_error(line, "duplicate android:id '%s' (first declared at line %d)",
                       id, declared_ids.lines[prev]);
        else
            idlist_add(&declared_ids, id, line);

        Frame *group = strcmp(f->name, "RadioButton") == 0 ? enclosing_radio_group() : NULL;
        if (group)
            idlist_add(&group->radio_ids, id, line);
    }
    else if (strcmp(attr, "android:layout_width") == 0 ||
             strcmp(attr, "android:layout_height") == 0) {
        if (strcmp(value, "wrap_content") != 0 &&
            strcmp(value, "match_parent") != 0 &&
            !(leading_int(value, &n) && n > 0))
            diag_error(line, "%s has invalid value \"%s\" "
                       "(expected wrap_content, match_parent or a positive size)",
                       attr, value);
    }
    else if (strcmp(attr, "android:padding") == 0) {
        if (leading_int(value, &n) && n <= 0)
            diag_error(line, "android:padding must be > 0, got %ld", n);
    }
    else if (strcmp(attr, "android:progress") == 0) {
        if (leading_int(value, &n)) {
            if (n < 0)
                diag_error(line, "android:progress must be >= 0, got %ld", n);
            f->has_progress = 1;
            f->progress = n;
        }
    }
    else if (strcmp(attr, "android:max") == 0) {
        if (leading_int(value, &n)) {
            f->has_max = 1;
            f->max = n;
        }
    }
    else if (strcmp(attr, "android:checkedButton") == 0 && is_radio_group(f)) {
        const char *id = id_name(value);
        if (!id) {
            diag_error(line, "android:checkedButton must be \"@id/name\", got \"%s\"", value);
            return;
        }
        free(f->checked_button);
        f->checked_button = xstrdup(id);
        f->checked_line = line;
    }
    else if (strcmp(attr, "android:count") == 0 && is_radio_group(f)) {
        if (!leading_int(value, &n) || n <= 0) {
            diag_error(line, "android:count must be a positive integer, got \"%s\"", value);
            return;
        }
        f->has_count = 1;
        f->declared_count = n;
    }
}

/* Checks that need every attribute of the current start tag. */
static void finish_attributes(void) {
    Frame *f = top();
    if (f->has_max && f->has_progress && f->progress > f->max)
        diag_error(f->line, "android:progress (%ld) is greater than android:max (%ld) in <%s>",
                   f->progress, f->max, f->name);
}

/* Pops the current element. end_name is NULL for a self-closing tag. */
static void close_element(const char *end_name, int end_line) {
    Frame *f = top();

    if (end_name && strcmp(end_name, f->name) != 0)
        diag_error(end_line, "closing tag </%s> does not match <%s> opened at line %d",
                   end_name, f->name, f->line);

    if (is_radio_group(f)) {
        if (f->checked_button && idlist_find(&f->radio_ids, f->checked_button) < 0)
            diag_error(f->checked_line,
                       "android:checkedButton '%s' is not a RadioButton in this RadioGroup",
                       f->checked_button);
        if (f->has_count && f->declared_count != f->radio_count)
            diag_error(f->line, "RadioGroup declares android:count=%ld but contains %ld RadioButton(s)",
                       f->declared_count, f->radio_count);
    }

    free_frame(f);
    depth--;
}
%}

%locations
%define parse.error verbose

%union {
    char *str;
}

%token <str> NAME "name" STRING "string"
%token LT "<" GT ">" SLASH_GT "/>" END_LT "</" EQ "="
%destructor { free($$); } <str>

%start document

%%

document:
      elements
;

elements:
      element
    | elements element
;

element:
      open_tag attributes ">" { finish_attributes(); } content "</" NAME ">"
      {
          close_element($7, @7.first_line);
          free($7);
      }
    | open_tag attributes "/>"
      {
          finish_attributes();
          close_element(NULL, @3.first_line);
      }
;

open_tag:
      "<" NAME { open_element($2, @2.first_line); }
;

attributes:
      %empty
    | attributes NAME "=" STRING
      {
          char *value = unquote($4);
          check_attribute($2, value, @2.first_line);
          free(value);
          free($2);
          free($4);
      }
;

content:
      %empty
    | elements
;

%%

void yyerror(const char *s) {
    diag_error(yylloc.first_line, "%s", s);
}

static void usage(FILE *out, const char *prog) {
    fprintf(out,
            "usage: %s [-t] [file.xml]\n"
            "  Reads standard input when no file is given.\n"
            "  -t, --tokens   print each token as it is scanned\n"
            "  -h, --help     show this help\n",
            prog);
}

int main(int argc, char **argv) {
    const char *path = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-t") == 0 || strcmp(argv[i], "--tokens") == 0) {
            trace_tokens = 1;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(stdout, argv[0]);
            return 0;
        } else if ((argv[i][0] == '-' && argv[i][1] != '\0') || path) {
            usage(stderr, argv[0]);
            return 2;
        } else {
            path = argv[i];
        }
    }

    if (path && strcmp(path, "-") != 0) {
        yyin = fopen(path, "r");
        if (!yyin) {
            fprintf(stderr, "%s: %s\n", path, strerror(errno));
            return 2;
        }
        input_name = path;
    }

    int rc = yyparse();

    while (depth > 0)
        free_frame(&stack[--depth]);
    free(stack);
    idlist_free(&declared_ids);
    if (yyin && yyin != stdin)
        fclose(yyin);

    if (rc == 0 && error_count == 0) {
        printf("%s: valid\n", input_name);
        return 0;
    }
    fprintf(stderr, "%s: %d error%s\n", input_name, error_count, error_count == 1 ? "" : "s");
    return 1;
}
