// Known-answer probe for ghostwriter's Markdown layer. Reads a Markdown file (argv[1]) and prints
// the AST dump, the heading list and the rendered HTML so mayhem/test.sh can assert exact values.
#include <QFile>
#include <QString>
#include <QTextStream>
#include <QVector>
#include <memory>

#include "src/markdown/cmarkgfmapi.h"
#include "src/markdown/markdownast.h"
#include "src/markdown/markdownnode.h"

using namespace ghostwriter;

int main(int argc, char **argv)
{
    if (argc < 2) {
        return 2;
    }
    QFile file(QString::fromLocal8Bit(argv[1]));
    if (!file.open(QIODevice::ReadOnly)) {
        return 3;
    }
    const QString text = QString::fromUtf8(file.readAll());

    std::unique_ptr<MarkdownAST> ast(CmarkGfmAPI::instance()->parse(text, false));
    QTextStream out(stdout);
    out << "AST-BEGIN\n" << ast->toString() << "AST-END\n";
    for (MarkdownNode *heading : ast->headings()) {
        out << "HEADING level=" << heading->headingLevel() << " line=" << heading->startLine()
            << " atx=" << heading->isAtxHeading() << " setext=" << heading->isSetextHeading() << "\n";
    }
    MarkdownNode *block = ast->findBlockAtLine(5);
    out << "BLOCK-AT-5 " << (block ? block->toString() : QString("none")) << "\n";
    out << "HTML-BEGIN\n" << CmarkGfmAPI::instance()->renderToHtml(text, false) << "HTML-END\n";
    return 0;
}
