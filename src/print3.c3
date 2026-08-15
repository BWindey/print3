module print3;

import std::io;
import std::math;
import std::os::process;

import bufferedoutput;
import bufferedinput;

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

BufferedOutput buffered_output @local @noinit;
BufferedInput buffered_input @local @noinit;
BackedArenaAllocator* internal_allocator @local @noinit;
Process pager_process @local @noinit;

bool local_vars_started @local = false;

macro internal_print(String s) {
	buffered_output.write(s);
}

macro internal_print_char(char c) {
	buffered_output.write_byte(c);
}

<*
	Custom line nr printer as replacement for printf().

	@require line >= 0
*>
fn void print_line_nr(Print3LineNr nr_format, sz line) {
	// for buffer size: usz::max = 4_294_967_296 => 10 digits
	// sz cannot be negative, so no 11th char needed
	static char[10] nr_buffer;

	buffered_output.write(nr_format.pre);
	sz buffer_idx = 0;
	while (line > 0) {
		nr_buffer[9 - buffer_idx] = (char) (line % 10) + '0';
		line /= 10;
		buffer_idx += 1;
	}
	// buffer_idx == len of line-nr in printed chars

	if (nr_format.left_align) {
		buffered_output.write(nr_buffer[buffer_idx..]);
	}
	// padding
	for (int i = 0; i < nr_format.min_size - buffer_idx; i++) {
		buffered_output.write_byte(nr_format.padding_char);
	}
	if (!nr_format.left_align) {
		buffered_output.write(nr_buffer[10 - buffer_idx..]);
	}

	buffered_output.write(nr_format.post);
}

// This function will not strictly check validity to be as fast as possible
fn sz print_number(Print3Config config, String line, sz i) {
	sz number_end = i;

	if (line[number_end] == '0' && number_end + 1 < line.len) {
		switch (line[number_end + 1]) {
			case 'x':
			case 'b':
			case 'o':
				number_end += 2;
		}
	}

	while OUTER: (number_end < line.len) switch (line[number_end]) {
		case '0'..'9':
		case 'a'..'d':
		case 'A'..'D':
		case 'f':
		case 'F':
			number_end += 1;

		case '.':
		case '_':
			if (number_end + 1 < line.len) {
				switch (line[number_end + 1]) {
					case '0'..'9':
					case 'a'..'f':
					case 'A'..'F':
						number_end += 2;
					default: break OUTER;
				}
			} else { break OUTER; }

		case 'e':
		case 'E':
		case 'p':
		case 'P':
			if (number_end + 1 < line.len) {
				switch (line[number_end + 1]) {
					case '0'..'9':
					case 'a'..'f':
					case 'A'..'F':
						number_end += 2;

					case '-':
					case '+':
						if (number_end + 2 < line.len) {
							switch (line[number_end + 2]) {
								case '0'..'9':
								case 'a'..'f':
								case 'A'..'F':
									number_end += 3;

								default: break OUTER;
							}
						} else { break OUTER; }

					default: break OUTER;
				}
			} else {
				// assume just part of hex
				number_end += 1;
			}

		default: break OUTER;
	}

	if (number_end < line.len && line[number_end].to_lower() == 'u') number_end += 1;
	if (number_end < line.len && line[number_end].to_lower() == 'l') number_end += 1;
	if (number_end < line.len && line[number_end].to_lower() == 'l') number_end += 1;

	buffered_output.write(config.theme.number);
	buffered_output.write(line[i..number_end - 1]);
	buffered_output.write(Ansi.RESET);

	return number_end;
}

fn sz print_doc_contract(Print3Config config, String line, sz idx) {
	sz start_comment = idx;
	while (idx < line.len) {
		if (idx + 1 < line.len && line[idx:2] == "*>") {
			idx += 2;
			in_doc_contract = false;
			break;
		}
		idx += 1;
	}

	buffered_output.write(config.theme.comment);
	buffered_output.write(line[start_comment..idx - 1]);
	buffered_output.write(Ansi.RESET);

	return idx;
}

fn String replace_tabs(String line, char spaces_per_tab) {
	int tab_count = 0;
	foreach (char c : line) if (c == '\t') tab_count += 1;

	if (tab_count == 0) return line;

	String replaced_line = (String) alloc::alloc_array(
		internal_allocator, char, line.len + tab_count * ((sz) spaces_per_tab - 1)
	);

	sz idx = 0;
	foreach (char c : line) {
		if (c == '\t') {
			for (char i = 0; i < spaces_per_tab; i++) {
				replaced_line[idx] = ' ';
				idx++;
			}
		} else {
			replaced_line[idx] = c;
			idx++;
		}
	}

	return replaced_line;
}

// TODO: use symbol colour for escape sequences in strings
// TODO: support doc contracts
// TODO: for lines that do not get printed, add a scan for opening/closing
//       contracts, strings, comments, ...

sz comment_depth = 0;
bool in_raw_string = false;
bool in_doc_contract = false;

fn void print_line(Print3Config config, String line, sz i) @local {
	sz chars_printed = 0;
	if (config.add_line_nr) {
		print_line_nr(config.nr_format, i);
	}

	line = replace_tabs(line, config.spaces_per_tab);

	sz idx = 0;

	// Handle multiline comments / comment blocks
	if (comment_depth > 0) buffered_output.write(config.theme.comment)!!;
	sz start_comment = idx;
	while (comment_depth > 0 && idx < line.len) {
		if (idx + 1 < line.len && line[idx:2] == "/*") {
			comment_depth += 1;
			idx += 2;
		} else if (idx + 1 < line.len && line[idx:2] == "*/") {
			comment_depth -= 1;
			idx += 2;
		} else {
			idx++;
		}
	}
	if (idx > start_comment) {
		buffered_output.write(line[start_comment..idx - 1])!!;
		if (comment_depth <= 0) buffered_output.write(Ansi.RESET)!!;
	}
	if (idx >= line.len) buffered_output.write(Ansi.RESET)!!;

	// Handle multiline raw strings
	if (in_raw_string) buffered_output.write(config.theme.string)!!;
	while (in_raw_string && idx < line.len) {
		if (line[idx] == '`') {
			in_raw_string = false;
			buffered_output.write_byte('`')!!;
			buffered_output.write(Ansi.RESET)!!;
		} else {
			buffered_output.write_byte(line[idx])!!;
		}
		idx++;
	}
	if (idx >= line.len) buffered_output.write(Ansi.RESET)!!;

	if (in_doc_contract) {
		idx = print_doc_contract(config, line, idx);
	}

	// Handle rest
	while (idx < line.len) {
		switch (line[idx]) {
			case ' ':
				buffered_output.write_byte(' ')!!;
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
					buffered_output.write(config.theme.comment)!!;
					buffered_output.write(line[idx..end_of_comment])!!;
					buffered_output.write(Ansi.RESET)!!;
					idx = end_of_comment + 1;
				} else {
					nextcase;
				}

			case '<':
				if (idx + 1 < line.len && line[idx + 1] == '*') {
					in_doc_contract = true;
					idx = print_doc_contract(config, line, idx);
				} else {
					nextcase;
				}

			case '.':
			case ',':
			case '(': case ')':
			case '[': case ']':
			case '{': case '}':
			case '>':
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
				buffered_output.write(config.theme.symbol)!!;
				buffered_output.write_byte(line[idx])!!;
				buffered_output.write(Ansi.RESET)!!;
				idx++;

			case '\'':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '\'' || is_escaped_char(line, idx))
				) { idx++; }
				buffered_output.write(config.theme.string)!!;
				buffered_output.write(line[word_start_idx..idx])!!;
				buffered_output.write(Ansi.RESET)!!;
				idx++;

			case '"':
				sz word_start_idx = idx;
				idx++;
				while (
					idx < line.len && (line[idx] != '"' || is_escaped_char(line, idx))
				) { idx++; }
				buffered_output.write(config.theme.string)!!;
				buffered_output.write(line[word_start_idx..idx])!!;
				buffered_output.write(Ansi.RESET)!!;
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
				buffered_output.write(config.theme.string)!!;
				buffered_output.write(line[word_start_idx..idx])!!;
				buffered_output.write(Ansi.RESET)!!;
				idx++;

			case '0'..'9':
				idx = print_number(config, line, idx);

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
					buffered_output.write(config.theme.constant)!!;
					buffered_output.write(word)!!;
					buffered_output.write(Ansi.RESET)!!;
				} else {
					buffered_output.write(config.theme.type)!!;
					buffered_output.write(word)!!;
					buffered_output.write(Ansi.RESET)!!;
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
					buffered_output.write(Ansi.BOLD)!!;
				}
				buffered_output.write(config.theme.at)!!;
				buffered_output.write(line[word_start_idx..word_end_idx])!!;
				buffered_output.write(Ansi.RESET)!!;

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
					case "alias":
					case "assert":
					case "asm":
					case "attrdef":
					case "attrgroup":
					case "attrmacro":
					case "bitstruct":
					case "break":
					case "case":
					case "catch":
					case "constdef":
					case "const":
					case "constset":
					case "cenum":
					case "continue":
					case "default":
					case "defer":
					case "do":
					case "else":
					case "enum":
					case "extern":
					case "false":
					case "excuse":
					case "faultdef":
					case "faultset":
					case "faultconst":
					case "for":
					case "foreach":
					case "foreach_r":
					case "fn":
					case "tlocal":
					case "if":
					case "inline":
					case "import":
					case "lengthof":
					case "macro":
					case "module":
					case "nextcase":
					case "null":
					case "interface":
					case "return":
					case "static":
					case "struct":
					case "switch":
					case "true":
					case "try":
					case "typedef":
					case "distinct":
					case "union":
					case "var":
					case "while":
					case "$assert":
					case "$case":
					case "$default":
					case "$defined":
					case "$echo":
					case "$else":
					case "$embed":
					case "$endfor":
					case "$endforeach":
					case "$endif":
					case "$endswitch":
					case "$eval":
					case "$error":
					case "$exec":
					case "$expand":
					case "$feat":
					case "$feature":
					case "$for":
					case "$foreach":
					case "$if":
					case "$include":
					case "$reflect":
					case "$stringify":
					case "$switch":
					case "$Typefrom":
					case "$Typeof":
					case "$vaarg":
						buffered_output.write(config.theme.keyword)!!;
						buffered_output.write(word)!!;
						buffered_output.write(Ansi.RESET)!!;
					case "void":
					case "bool":
					case "char":
					case "double":
					case "float":
					case "float16":
					case "bfloat":
					case "int128":
					case "ichar":
					case "int":
					case "iptr":
					case "sz":
					case "long":
					case "short":
					case "uint128":
					case "uint":
					case "ulong":
					case "uptr":
					case "ushort":
					case "usz":
					case "float128":
					case "any":
					case "fault":
					case "typeid":
					case "untypedlist":
						buffered_output.write(config.theme.type)!!;
						buffered_output.write(word)!!;
						buffered_output.write(Ansi.RESET)!!;
					default:
						if (line[word_start_idx] == '$') {
							buffered_output.write(config.theme.comptime_ident)!!;
							buffered_output.write(word)!!;
							buffered_output.write(Ansi.RESET)!!;
						} else if (idx < line.len && line[idx] == '(') {
							buffered_output.write(Ansi.BOLD)!!;
							buffered_output.write(config.theme.call)!!;
							buffered_output.write(word)!!;
							buffered_output.write(Ansi.RESET)!!;
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
							buffered_output.write(config.theme.member)!!;
							buffered_output.write(word)!!;
							buffered_output.write(Ansi.RESET)!!;
						} else {
							buffered_output.write(word)!!;
						}
				}
		}
	}

	sz foo = 0;
	if (line.len == 0 || line[^1] != '\n') buffered_output.write_byte('\n')!!;
}

fn void setup_print_file(Allocator allocator, Print3Config config) {
	if (local_vars_started) return;

	internal_allocator = allocators::new_backed_allocator(
		config.print_buffer_size + BufferedOutput::size + 2048u,
		allocator
	)!!;

	buffered_output = bufferedoutput::new(
		internal_allocator, config.print_buffer_size
	);

	buffered_input = bufferedinput::new(
		internal_allocator,
		config.read_buffer_size,
		null
	);

	local_vars_started = true;

	if (config.use_pager) setup_pager(config);
}

fn void cleanup_print_file(Print3Config config) {
	buffered_output.flush()!!;
	internal_allocator.destroy();

	if (config.use_pager) pager_process.join()!!;
}

fn void setup_pager(Print3Config config) {
	static File pager_stdin;
	Process? p = process::spawn(
		{ "less", "-R" },
		options: INHERIT_ENV,
		in: process::CAPTURE,
		out: process::INHERIT,
		err: process::INHERIT
	);
	if (catch p) {
		error("Failed to spawn 'less -R' to use as pager", code: 60);
	}
	pager_process = p;

	if (!pager_process.stdin_file) {
		error("Failed to get stdin file from less process", code: 61);
	}
	pager_stdin = file::from_handle(pager_process.stdin_file);
	buffered_output.output = &pager_stdin;
}


fn void? print_file(Print3Config config, String file_name) {
	assert(local_vars_started == true);
	File open_file = file::open(file_name, "r")!;
	defer open_file.close();

	buffered_input.set_new_input(&open_file);

	comment_depth = 0;
	in_raw_string = false;

	sz i = 0;
	sz line_alloc_mark = internal_allocator.mark();
	while (try line = buffered_input.readline()) {
		i++;
		if (config.line_start >= 0 && i < config.line_start) continue;
		if (config.line_stop >= 0 && i > config.line_stop) continue;

		print_line(config, line, i);
		internal_allocator.reset(line_alloc_mark);
	}

	buffered_output.flush();
}
