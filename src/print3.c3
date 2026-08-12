module print3;
import std::io;
import std::encoding::experimental::regex;
import std::math;


macro bool is_escaped_char(String line, sz idx) {
	if (idx == 0) return false;

	idx--;
	sz backslash_counter = 0;

	while (idx > 0 && line[idx] == '\\') {
		idx--;
		backslash_counter++;
	}

	return backslash_counter % 2 != 0;
}

Regex number_regex @local @noinit;
String tab_replacement @local @noinit;
sz nr_format_len @local @noinit;
bool local_vars_started @local = false;

fn sz String.visual_len(self) {
	sz len = 0;
	for (sz i = 0; i < self.len;) {
		char c = self[i];
		switch (c) {
			// Visible ASCII
			case 32..126:
				len += 1;
				i += 1;

			// UTF-8 multibyte
			case 0b1100_0000..0b1101_1111:
				len += 1;
				i += 2;
			case 0b1110_0000..0b1110_1111:
				len += 1;
				i += 3;
			case 0b1111_0000..0b1111_0111:
				len += 1;
				i += 4;

			case 0..31:
			case 127:
				i += 1;

			default:
				// Should not happen but I don't really want it to crash...
				i += 1;
		}
	}

	return len;
}

fn void print_number(Print3Config config, String line, sz* i) {
	Match m = number_regex.first_match(line[*i..])!!;
	sz number_end_idx = *i + m.end;
	io::printf(
		"%s%s%s",
		config.theme.number,
		line[*i:m.end],
		Ansi.RESET
	);
	*i += m.end;
}

// TODO: use symbol colour for escape sequences in strings
// TODO: support doc contracts
fn void print_line(Print3Config config, String line, sz i) => @pool() {
	if (config.add_line_nr) io::printf(config.nr_format, i)!!;

	line = line.treplace("\t", tab_replacement);

	sz idx = 0;
	static sz comment_depth = 0;
	static bool in_raw_string = false;

	// Handle multiline comments / comment blocks
	if (comment_depth > 0) io::print(config.theme.comment);
	while (comment_depth > 0 && idx < line.len) {
		if (idx + 1 < line.len && line[idx:2] == "/*") {
			comment_depth++;
			idx += 2;
			io::print("/*");
			continue;
		}

		if (idx + 1 < line.len && line[idx:2] == "*/") {
			io::print("*/");
			comment_depth--;
			idx += 2;
			if (comment_depth == 0) {
				io::print(Ansi.RESET);
			}
		} else {
			io::printf("%c", line[idx]);
			idx++;
		}
	}
	if (idx >= line.len) io::print(Ansi.RESET);

	// Handle multiline raw strings
	if (in_raw_string) io::print(config.theme.string);
	while (in_raw_string && idx < line.len) {
		if (line[idx] == '`') {
			in_raw_string = false;
			io::printf("`%s", Ansi.RESET);
		} else {
			io::printf("%c", line[idx]);
		}
		idx++;
	}
	if (idx >= line.len) io::print(Ansi.RESET);

	// Handle rest
	while (idx < line.len) {
		switch (line[idx]) @jump {
			case ' ':
				io::print(" ");
				idx++;

			case '/':
				if (idx + 1 < line.len) {
					sz end_of_comment;
					if (line[idx + 1] == '/') {
						end_of_comment = line.len - 1;
					} else if (line[idx + 1] == '*') {
						end_of_comment = idx + 3;
						while (
							end_of_comment < line.len
							&& line[end_of_comment - 1:2] != "*/"
						) {
							end_of_comment++;
						}
						if (end_of_comment >= line.len) {
							end_of_comment = line.len - 1;
							comment_depth += 1;
						}
					} else {
						nextcase;
					}
					io::printf(
						"%s%s%s",
						config.theme.comment, line[idx..end_of_comment], Ansi.RESET
					);
					idx = end_of_comment + 1;
				} else {
					nextcase;
				}

			case '.':
			case ',':
			case '(': case ')':
			case '[': case ']':
			case '{': case '}':
			case '<': case '>':
			case '+': case '-':
			case '*':
			case '%':
			case '^':
			case ':':
			case ';':
			case '=':
			case '?':
			case '!':
			case '|':
			case '&':
			case '~':
				io::printf("%s%c%s", config.theme.symbol, line[idx], Ansi.RESET);
				idx++;

			case '\'':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '\'' || is_escaped_char(line, idx))
				) { idx++; }
				io::printf(
					"%s%s%s",
					Ansi.BRIGHT_GREEN, line[word_start_idx..idx], Ansi.RESET
				);
				idx++;

			case '"':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '"' || is_escaped_char(line, idx))
				) { idx++; }
				io::printf(
					"%s%s%s",
					Ansi.BRIGHT_GREEN, line[word_start_idx..idx], Ansi.RESET
				);
				idx++;
			case '`':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '`' || is_escaped_char(line, idx))
				) { idx++; }
				if (idx == line.len) {
					idx--;
					in_raw_string = true;
				}
				io::printf(
					"%s%s%s",
					Ansi.BRIGHT_GREEN, line[word_start_idx..idx], Ansi.RESET
				);
				idx++;

			case '0'..'9':
				print_number(config, line, &idx);

			case 'A'..'Z':
				sz word_start_idx = idx;
				bool is_al_caps = true;
				idx++;

				while (
					idx < line.len &&
					(ascii::@is_alnum(line[idx]) || line[idx] == '_')
				) {
					if (ascii::@is_lower(line[idx])) is_al_caps = false;
					idx++;
				}
				sz word_end_idx = idx - 1;
				String word = line[word_start_idx..word_end_idx];

				if (is_al_caps) {
					io::printf("%s%s%s", Ansi.BRIGHT_MAGENTA, word, Ansi.RESET);
				} else {
					io::printf("%s%s%s", Ansi.BRIGHT_YELLOW, word, Ansi.RESET);
				}

			case '@':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len &&
					(ascii::@is_alnum(line[idx]) || line[idx] == '_')
				) {
					idx++;
				}
				sz word_end_idx = idx - 1;
				if (idx < line.len && line[idx] == '(') {
					io::print(Ansi.BOLD);
				}
				io::printf(
					"%s%s%s",
					Ansi.BRIGHT_CYAN,
					line[word_start_idx..word_end_idx],
					Ansi.RESET
				);

			default:
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len &&
					(ascii::@is_alnum(line[idx]) || line[idx] == '_')
				) {
					idx++;
				}
				sz word_end_idx = idx - 1;
				String word = line[word_start_idx..word_end_idx];

				switch (word) {
					case "fn":
					case "macro":
					case "return":
					case "module":
					case "import":
					case "switch":
					case "case":
					case "default":
					case "nextcase":
					case "if":
					case "else":
					case "while":
					case "do":
					case "for":
					case "foreach":
					case "foreach_r":
					case "try":
					case "catch":
					case "true":
					case "false":
					case "enum":
					case "struct":
					case "union":
					case "assert":
					case "faultdef":
					case "attrdef":
					case "typedef":
					case "const":
					case "static":
					case "alias":
					case "var":
					case "$for":
					case "$endfor":
					case "$endforeach":
					case "$endif":
					case "$endswitch":
					case "$if":
					case "$else":
					case "$switch":
					case "$case":
					case "$default":
					case "$echo":
					case "$error":
					case "$eval":
					case "$evaltype":
					case "$exec":
					case "$extnameof":
						io::printf("%s%s%s", Ansi.BRIGHT_RED, word, Ansi.RESET);
					case "float":
					case "double":
					case "bool":
					case "int":
					case "uint":
					case "long":
					case "ulong":
					case "char":
					case "ichar":
					case "short":
					case "ushort":
					case "sz":
					case "usz":
					case "void":
						io::printf("%s%s%s", Ansi.BRIGHT_YELLOW, word, Ansi.RESET);
					default:
						if (line[word_start_idx] == '$') {
							io::printf(
								"%s%s%s",
								Ansi.BRIGHT_CYAN, word, Ansi.RESET
							);
						} else if (idx < line.len && line[idx] == '(') {
							io::printf(
								"%s%s%s%s",
								Ansi.BOLD, Ansi.BRIGHT_GREEN, word, Ansi.RESET
							);
						} else if (
							word_start_idx - 1 >= 0
							&& line[word_start_idx - 1] == '.'
							&& (
								word_start_idx - 2 < 0
								|| line[word_start_idx - 2].is_alnum()
								|| line[word_start_idx - 2].is_blank()
								|| line[word_start_idx - 2] == '_'
								|| line[word_start_idx - 2] == '{'
								|| line[word_start_idx - 2] == ']'
							)
						) {
							io::printf("%s%s%s", Ansi.BRIGHT_BLUE, word, Ansi.RESET);
						} else {
							io::print(word);
						}
				}
		}
	}

	if (line.len == 0 || line[^1] != '\n') io::print("\n");
}

fn void? print_file(Print3Config config, String file_name) => @pool() {
	if (!local_vars_started) {
		number_regex = regex::compile(
			tmem,
			`^[-+]?(`
			`0x[0-9a-f](_?[0-9a-f])*(\.[0-9a-f](_?[0-9a-f])*p[+-]?[0-9](_?[0-9])*[fd]?|u?l{0,2})|`
			`(0b[01](_?[01])*|0o[0-7](_?[0-7])*)(u?l{0,2})|`
			`[0-9](_?[0-9])*(\.[0-9](_?[0-9])*(e[+-]?[0-9](_?[0-9])*)?[fd]?|e[+-]?[0-9](_?[0-9])*[fd]?|u?l{0,2})`
			`)`,
			EXTENDED
		)!!;

		tab_replacement = (String) alloc::new_array(
			tmem, char, config.spaces_per_tab
		);
		mem::set(&tab_replacement[0], ' ', config.spaces_per_tab);

		if (config.add_line_nr) {
			nr_format_len = config.nr_format.visual_len();

		} else {
			nr_format_len = 0;
		}

		local_vars_started = true;
	}


	File open_file = file::open(file_name, "r")!;
	defer open_file.close();

	sz i = 0;
	while (try line = io::treadline(&open_file)) {
		i++;
		if (config.line_start >= 0 && i < config.line_start) continue;
		if (config.line_stop >= 0 && i > config.line_stop) continue;

		// TODO:
		// - truncate too long lines (80)
		print_line(config, line, i);
	}
}
