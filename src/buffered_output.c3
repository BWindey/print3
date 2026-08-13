module bufferedoutput;
import std::io;

struct BufferedOutput {
	sz written;
	File* output;
	char[] buffer;
}

fn BufferedOutput new(Allocator allocator, sz size, File* output = io::stdout()) {
	return {
		.written = 0,
		.output = output,
		.buffer = alloc::new_array(allocator, char, size),
	};
}

fn void? BufferedOutput.write_byte(&self, char byte) @maydiscard {
	self.buffer[self.written] = byte;
	self.written++;
	if (self.written >= self.buffer.len) {
		self.output.write(self.buffer)!;
		self.written = 0;
	}
}

fn void? BufferedOutput.write(&self, char[] bytes) @maydiscard {
	if (bytes.len >= self.buffer.len) {
		if (self.written > 0) {
			self.output.write(self.buffer[:self.written])!;
			self.written = 0;
		}
		self.output.write(bytes)!;
		return;
	}

	// Ensure that there is room
	if (self.written + bytes.len > self.buffer.len) {
		self.output.write(self.buffer[:self.written])!;
		self.written = 0;
	}

	mem::copy(&self.buffer[self.written], bytes.ptr, bytes.len);
	self.written += bytes.len;

	if (self.written >= self.buffer.len) {
		self.output.write(self.buffer)!;
		self.written = 0;
	}
}

fn void? BufferedOutput.flush(&self) @maydiscard {
	if (self.written > 0) {
		self.output.write(self.buffer[:self.written])!;
		self.written = 0;
	}
	self.output.flush()!!;
}
