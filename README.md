# Print3

A `cat`-like programming built for C3 source files, it will try to highlight
the source like inside an editor.

Example:
![image of the ./example/example.c3 file when printed by print3](./example/example.png)


## Usage:

```
 ./print3 [options...] file(s)

 Print C3 files with colours. A bit akin to 'cat' or 'bat'.

 Options and files can generally be mixed, only when an option requires
 an argument, it is expected to follow directly behind.

 Available options:
  -h, --help              Show this help message

  --tabsize <number>      Amount of spaces to print for a tab character
  --maxcol <number>       Max length of a line, truncates rest
  --ellipsis <text>       Ellipsis to use when truncating
  -n, --number            Show line numbers
  --nonumber              Show no line numbers
  --nrformat <text>       Format for numbers (f.e. "%d | ")
  --line-start <number>   Start printing from this line (inclusive)
  --line-stop <number>    Stop printing at this line (inclusive)

  --colour-<thing> <text> Set the colour for <thing> to <text>, should be
                          specified in "#RRGGBB" format. Available things:
                          at, call, comment, comptime_ident, constant, ident,
                          keyword, member, number, string, symbol, type.
```


## Known issues:
- `--maxcol` and `--ellipsis` currently do not work
- `--colour-<thing>` colour parsing does not seem to work


## Improvement points:
- profile performance and improve where possible
- add json config file for easier default overrides
- add either builtin pager, or auto-pipe to `less` or `more` from within `print3`

