# Building

To build this site, you need zine

Just clone the repository
```
git clone https://github.com/ikks/flow-control.dev.git
cd flow-control.dev
```
and issue

```
zine
```

Then visit with your browser the site pointed by the previous command

Powered by [Zine](https://zine-ssg.io/docs/)

## Adding icons

We have trimmed the list of icons that come from Nerdfonts, to add an icon:

Browse in https://www.nerdfonts.com/cheat-sheet and look for the icon to be
added.

1. Update the file `contrib/symbolnerdfontmonolist.txt` adding the unicode
2. Add the reference to assets/css/webfont.css
3. Use it the same as layouts/templates/base.html navbar
4. Update the fonts installing (uv pip install fonttools) with:

```python
pyftsubset contrib/fonts/nerdfonts/SymbolsNerdFontMono-Regular.ttf --unicodes-file=contrib/symbolnerdfontmonolist.txt  --output-file=assets/fonts/SymbolsNerdFontMono-Regular.ttf
```

If the icon you want to use from nerdonfts is not present in contrib/fonts/nerdfonts
get it from https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/NerdFontsSymbolsOnly.zip
and update contrib to ease later needings.

## Resources

* [Monospace Web Theme](https://owickstrom.github.io/the-monospace-web/)
* [Zine](https://zine-ssg.io/docs/)
* [Flow Control Editor](https://github.com/neurocyte/flow)
* [NerdFonts](https://www.nerdfonts.com/cheat-sheet)
