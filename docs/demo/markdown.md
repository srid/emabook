---
page:
  headHtml: |
    <link href="https://cdn.jsdelivr.net/npm/prismjs@1.23.0/themes/prism-tomorrow.css" rel="stylesheet" />
    <script src="https://cdn.jsdelivr.net/combine/npm/prismjs@1.23.0/prism.min.js,npm/prismjs@1.23.0/plugins/autoloader/prism-autoloader.min.js"></script>
---
# *Extended* Markdown :writing_hand:

Emanote notes are written in Markdown format. A tutorial is [available here](https://commonmark.org/help/tutorial/). Below we shall highlight some of the commonmark extensions that Emanote supports on top of standard Mardown syntax.

## Wiki Links

You can link to a note by placing the filename (without extension) inside double square brackets. For example, `[[neuron]]` links to the file `neuron.md` and it will be rendered as [[neuron]]. Note that it is using the title of the note automatically;
you can specify a custom title as `[[neuron|Moving off neuron]]` which renders as [[neuron|Moving off neuron]] or even force use of filename with `[[neuron|neuron]]` which renders as [[neuron|neuron]].

Broken links render differently, for example: [[Foo bar]]

## Emojis

:smile:

:runner: :ant:

See [list of available emojis](https://gist.github.com/rxaviers/7360908) for reference.

## Footnotes

https://github.com/jgm/commonmark-hs/blob/master/commonmark-extensions/test/footnotes.md

Demo: Checkout this note[^1] and this other note[^2] as both are footnotes.

## Task lists

- [x] A task that was done
- [ ] A task that is to be done.
- A list item with no task marker

Tasks can also be written outside of list context, such as paragraphs:

[ ] This is a task on its own paragraph.

[x] Here we have the next paragraph.

## Definition lists

https://github.com/jgm/commonmark-hs/blob/master/commonmark-extensions/test/definition_lists.md

Fruits
: Apples
: Oranges

Animal Foods
: Eggs
: Diary
: Offal
: Muscle meat

## Tables

| Category      | Favourite      |
| ------------- | -------------- |
| Web Browser   | [Brave]        |
| Search Engine | [Brave Search] |
| Chat          | [Element]      |

[Brave]: https://brave.com/
[Brave Search]: https://search.brave.com/
[Element]: https://element.io/

## Hash Tags

Add Twitter-like hashtags anywhere in Markdown file. They can also be added to the YAML frontmatter. Hash tags can also be "hierarchical", for instance: #emanote/syntax/demo

### Hightlighting

You can highlight any ==inline text== by wraping them in `==` (ie. `==inline text==`).[^prop] The CSS style for highlighted inlines can be specified in [[custom-style|index.yaml]]. 

[^prop]: See original proposal for this syntax [here](https://talk.commonmark.org/t/highlighting-text-with-the-mark-element/840).

## Code Syntax Highlighting

In order to enable syntax highlighting, you must use a client-side JavaScript highlighter, such as [PrismJS](https://prismjs.com/), and add it to `page.headHtml` of [[yaml-config]] (if adding to all or multiple routes) or Markdown frontmatter (if adding to a single route):

```yaml
page:
  headHtml: |
    <link href="https://cdn.jsdelivr.net/npm/prismjs@1.23.0/themes/prism-tomorrow.css" rel="stylesheet" />
    <script src="https://cdn.jsdelivr.net/combine/npm/prismjs@1.23.0/prism.min.js,npm/prismjs@1.23.0/plugins/autoloader/prism-autoloader.min.js"></script>
```

Example using PrismJS:

```python
def fib(n):
    a, b = 0, 1
    while a < n:
        print(a, end=' ')
        a, b = b, a+b
    print()
fib(1000)
```

[^1]: Reference to a note.
[^2]: Another reference to a note.
