module print3;
import std::io;
import std::os;
import std::collections::list;

const String HELP_MESSAGE =
` ./print3 [options...] file(s)

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
`;


struct Print3Theme {
	String at;
	String call;
	String comment;
	String comptime_ident;
	String constant;
	String ident;
	String keyword;
	String member;
	String number;
	String string;
	String symbol;
	String type;
}

struct Print3Config {
	char spaces_per_tab;
	bool add_line_nr;
	int max_col;         // < 0 for no limit
	sz line_start;       // inclusive
	sz line_stop;        // inclusive, < 0 for no limit
	String ellipsis;
	String nr_format;
	List{String} files;
	Print3Theme theme;
}

const Print3Config DEFAULT_CONFIG = {
	.spaces_per_tab = 4,
	.add_line_nr = true,
	.max_col = -1,
	.line_start = 0,
	.line_stop = -1,
	.ellipsis = "...",
	.nr_format = "%3d \u2502 ",
	.theme = {
		.at = Ansi.BRIGHT_CYAN,
		.call = Ansi.BRIGHT_GREEN,
		.comment = ansi::color(0x92_83_74),
		.comptime_ident = Ansi.BRIGHT_CYAN,
		.constant = Ansi.BRIGHT_MAGENTA,
		.ident = "",
		.keyword = Ansi.BRIGHT_RED,
		.member = Ansi.BRIGHT_BLUE,
		.number = Ansi.BRIGHT_MAGENTA,
		.string = Ansi.BRIGHT_GREEN,
		.symbol = ansi::color(0xFE_80_19),
		.type = Ansi.BRIGHT_YELLOW,
	}
};

<*
	@require $letters.len > 0
*>
macro bool letter_in(char letter, char... $letters) {
	if (letter < 'A' || letter > 'z') return false;
	ulong $set = 0;
	$foreach $l : $letters:
		$assert $l >= 'A' &&& $l <= 'z';
		$set = $set | (1ul << ($l - 'A'));
	$endforeach
	return $set & (1ul << (letter - 'A')) != 0;
}

fn void error(String error_msg_format, args...) @noreturn @format(0) {
	io::eprint("Error: ");
	io::eprintfn(error_msg_format, ...args);
	io::eprintn("See 'print3 --help'.");
	os::exit(50);
}

fn void require_argument(String[] args, sz arg_idx) {
	if (arg_idx + 1 >= args.len) {
		error("%s rquires an argument.", args[arg_idx]);
	}
}

fn void check_nr_format(String nr_format) {
	sz perc_idx = 0;
	bool is_valid_format = false;
	while (try _perc_idx = nr_format.index_of_char_from('%', perc_idx)) {
		_perc_idx += 1;
		if (_perc_idx >= nr_format.len) break;

		// Only allow a single %..d, so if we already found one,
		// then this one should be an escaped percent: '%%'
		if (is_valid_format && nr_format[_perc_idx] != '%') {
			error(
				"--nrformat argument '%s' includes multiple '%%...d's, "
				"which is not allowed",
				nr_format
			);
		}

		// Skip forward so that '%-2d' is allowed
		if (nr_format[_perc_idx] == '-') _perc_idx += 1;
		while (_perc_idx < nr_format.len && nr_format[_perc_idx].is_digit()) {
			_perc_idx++;
		}

		if (
			_perc_idx < nr_format.len
			&& letter_in(nr_format[_perc_idx], 'd' , 's')
		) {
			is_valid_format = true;
		}
		perc_idx = _perc_idx + 1;
	}
	if (!is_valid_format) {
		error(
			"--nrformat argument '%s' does not include '%%d' for the number",
			nr_format
		);
	}
}

fn int parse_number(String argument, String number) {
	int? parsed_number = number.to_int();
	if (catch parsed_number) {
		error(
			"could not parse %s argument '%s' to an integer",
			argument, number
		);
	}
	return parsed_number;
}

fn String parse_colour(String argument, String colour) {
	if (colour[0] == '#') {
		if (colour.len != 7) {
			error(
				"colour for %s does not follow #RRGGBB format: '%s'",
				argument, colour
			);
		}
	} else if (colour.len != 6) {
		error(
			"colour for %s does not follow RRGGBB format: '%s'",
			argument, colour
		);
	}

	sz hex_start = 0;
	if (colour[0] == '#') hex_start = 1;

	String hex_string = colour[hex_start:6];
	uint? colour_rgb = hex_string.to_uint(base: 16);
	if (catch colour_rgb) {
		error(
			"colour '%s' for %s could not get parsed to an integer",
			colour, argument
		);
	}
	return string::tformat(
		"\e[38;2;%s;%s;%sm",
		colour_rgb >> 16,
		(colour_rgb & 0xFF00) >> 8,
		colour_rgb & 0xFF
	);
}

fn Print3Config parse_cli_args(String[] args) {
	Print3Config parsed_config = DEFAULT_CONFIG;
	parsed_config.files.tinit();

	for (sz arg_idx = 0; arg_idx < args.len; arg_idx++) {
		switch (args[arg_idx]) {
			case "-h":
			case "--help":
				io::print(HELP_MESSAGE);
				os::exit(0);

			case "--tabsize":
				require_argument(args, arg_idx);
				arg_idx += 1;
				int parsed_tab_size = parse_number(args[arg_idx - 1], args[arg_idx]);
				if (parsed_tab_size < 0 || parsed_tab_size > 16) {
					error(
						"passed tab size is out of the normal range (0-16): %d",
						parsed_tab_size
					);
				}
				parsed_config.spaces_per_tab = (char) parsed_tab_size;

			case "--maxcol":
				require_argument(args, arg_idx);
				arg_idx += 1;
				parsed_config.max_col = parse_number(args[arg_idx - 1], args[arg_idx]);

			case "--ellipsis":
				require_argument(args, arg_idx);
				arg_idx += 1;
				if (args[arg_idx].len > 4) {
					error(
						"--ellipsis argument '%s' is too long to use (len > 4)",
						args[arg_idx]
					);
				}
				parsed_config.ellipsis = args[arg_idx];

			case "-n":
			case "--number":
				parsed_config.add_line_nr = true;

			case "--nonumber":
				parsed_config.add_line_nr = false;

			case "--nrformat":
				require_argument(args, arg_idx);
				arg_idx += 1;
				check_nr_format(args[arg_idx]);
				parsed_config.nr_format = args[arg_idx];

			case "--line-start":
				require_argument(args, arg_idx);
				arg_idx += 1;
				parsed_config.line_start = parse_number(args[arg_idx - 1], args[arg_idx]);

			case "--line-stop":
				require_argument(args, arg_idx);
				arg_idx += 1;
				parsed_config.line_stop = parse_number(args[arg_idx - 1], args[arg_idx]);

			case "--colour-at":
				require_argument(args, arg_idx);
				parsed_config.theme.at = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-call":
				require_argument(args, arg_idx);
				parsed_config.theme.call = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-comment":
				require_argument(args, arg_idx);
				parsed_config.theme.comment = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-comptime_ident":
			case "--colour-comptime-ident":
				require_argument(args, arg_idx);
				parsed_config.theme.comptime_ident = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-constant":
				require_argument(args, arg_idx);
				parsed_config.theme.constant = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-ident":
				require_argument(args, arg_idx);
				parsed_config.theme.ident = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-keyword":
				require_argument(args, arg_idx);
				parsed_config.theme.keyword = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-member":
				require_argument(args, arg_idx);
				parsed_config.theme.member = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-number":
				require_argument(args, arg_idx);
				parsed_config.theme.number = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-string":
				require_argument(args, arg_idx);
				parsed_config.theme.string = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-symbol":
				require_argument(args, arg_idx);
				parsed_config.theme.symbol = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;
			case "--colour-type":
				require_argument(args, arg_idx);
				parsed_config.theme.type = parse_colour(args[arg_idx], args[arg_idx + 1]);
				arg_idx += 1;

			default:
				if (!file::is_file(args[arg_idx])) {
					error("'%s' is not a file", args[arg_idx]);
				}
				parsed_config.files.push(args[arg_idx]);
		}
	}

	return parsed_config;
}
