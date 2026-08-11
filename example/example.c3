module hello;
import std::collections::list;

struct Foo {
	int x;
	char* pointy;
}

fn void main() {
	Foo f = {
		.x = 324,
		.pointy = null,
	};
	double x = 12.3e11;
	double y = -1.3e-3;
}
