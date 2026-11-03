// Fuzzes the vendored cmark-gfm parser and all five renderers with the extension set
// ghostwriter attaches (src/markdown/cmarkgfmapi.cpp). Bytes 0-1 select parser options, byte 2 the
// wrap width; the remainder is the Markdown document.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "cmark-gfm.h"
#include "cmark-gfm-core-extensions.h"

static const char *const kExtensions[] = {"table", "strikethrough", "autolink", "tagfilter", "tasklist", NULL};

int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void)argc;
    (void)argv;
    cmark_gfm_core_extensions_ensure_registered();
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 3) {
        return -1;
    }

    static const int kOptionBits[] = {
        CMARK_OPT_SMART,
        CMARK_OPT_UNSAFE,
        CMARK_OPT_FOOTNOTES,
        CMARK_OPT_SOURCEPOS,
        CMARK_OPT_HARDBREAKS,
        CMARK_OPT_NOBREAKS,
        CMARK_OPT_VALIDATE_UTF8,
        CMARK_OPT_GITHUB_PRE_LANG,
        CMARK_OPT_LIBERAL_HTML_TAG,
        CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE,
        CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES,
        CMARK_OPT_FULL_INFO_STRING,
    };

    int options = CMARK_OPT_DEFAULT;
    const unsigned bits = data[0] | ((unsigned)data[1] << 8);
    for (int i = 0; i < 12; i++) {
        if (bits & (1u << i)) {
            options |= kOptionBits[i];
        }
    }
    int width = data[2];

    cmark_parser *parser = cmark_parser_new(options);
    for (const char *const *name = kExtensions; *name; ++name) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension(*name);
        if (!ext) {
            fprintf(stderr, "extension %s is not registered\n", *name);
            abort();
        }
        cmark_parser_attach_syntax_extension(parser, ext);
    }

    cmark_parser_feed(parser, (const char *)data + 3, size - 3);
    cmark_node *doc = cmark_parser_finish(parser);

    free(cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)));
    free(cmark_render_commonmark(doc, options, width));
    free(cmark_render_latex(doc, options, width));
    free(cmark_render_man(doc, options, width));
    free(cmark_render_xml(doc, options));

    cmark_node_free(doc);
    cmark_parser_free(parser);
    return 0;
}
