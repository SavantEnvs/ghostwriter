// Fuzzes ghostwriter's own Markdown layer: CmarkGfmAPI::parse() -> MarkdownAST/MarkdownNode
// (the AST that drives the editor highlighter and outline) plus CmarkGfmAPI::renderToHtml()
// (the live preview). Byte 0 bit 0 = smart typography; the rest is UTF-8 Markdown.
#include <QString>
#include <QVector>
#include <cstddef>
#include <cstdint>
#include <memory>

#include "src/markdown/cmarkgfmapi.h"
#include "src/markdown/markdownast.h"
#include "src/markdown/markdownnode.h"

using namespace ghostwriter;

static int walk(MarkdownNode *node)
{
    int sum = 0;
    for (; node != nullptr; node = node->next()) {
        sum += node->position() + node->length() + node->startLine() + node->endLine();
        sum += node->text().size() + node->toString().size();
        if (node->type() == MarkdownNode::Heading) {
            sum += node->headingLevel() + node->isSetextHeading() + node->isAtxHeading();
        }
        if (node->type() == MarkdownNode::ListItem || node->type() == MarkdownNode::TaskListItem) {
            sum += node->listItemNumber() + node->isNumberedListItem() + node->isBulletListItem();
        }
        sum += node->isInsideBlockquote() + node->isFencedCodeBlock();
        sum += walk(node->firstChild());
    }
    return sum;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size < 1) {
        return -1;
    }

    const bool smart = data[0] & 1;
    const QString text = QString::fromUtf8(reinterpret_cast<const char *>(data) + 1, static_cast<qsizetype>(size - 1));

    std::unique_ptr<MarkdownAST> ast(CmarkGfmAPI::instance()->parse(text, smart));
    volatile int sink = walk(ast->root());
    sink = sink + ast->toString().size();
    sink = sink + ast->headings().size();
    const int lines = text.count(QLatin1Char('\n')) + 1;
    for (int line = 0; line <= lines; line += (lines / 16) + 1) {
        MarkdownNode *block = ast->findBlockAtLine(line);
        if (block != nullptr) {
            sink = sink + block->startLine();
        }
    }
    sink = sink + CmarkGfmAPI::instance()->renderToHtml(text, smart).size();
    (void)sink;
    return 0;
}
