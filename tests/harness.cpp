#include "harness.hpp"

#include <cstdio>
#include <cstring>
#include <vector>

namespace slabtest {

namespace {

struct Entry {
	const char *name;
	TestFn fn;
};

std::vector<Entry> &registry() {
	static std::vector<Entry> r;
	return r;
}

const char *g_current = "";
int g_fails = 0;
int g_checks = 0;

} // namespace

int register_test(const char *p_name, TestFn p_fn) {
	registry().push_back(Entry{ p_name, p_fn });
	return int(registry().size());
}

void expect(bool p_ok, const char *p_what) {
	g_checks++;
	if (!p_ok) {
		g_fails++;
		std::fprintf(stderr, "FAIL [%s] %s\n", g_current, p_what);
	}
}

void expect_near(double p_got, double p_want, double p_tol, const char *p_what) {
	g_checks++;
	const double d = p_got - p_want;
	if (d > p_tol || d < -p_tol) {
		g_fails++;
		std::fprintf(stderr, "FAIL [%s] %s: got %f want %f\n", g_current, p_what, p_got, p_want);
	}
}

void expect_eq(long long p_got, long long p_want, const char *p_what) {
	g_checks++;
	if (p_got != p_want) {
		g_fails++;
		std::fprintf(stderr, "FAIL [%s] %s: got %lld want %lld\n", g_current, p_what, p_got, p_want);
	}
}

int run(const char *p_filter) {
	int ran = 0;
	for (const Entry &entry : registry()) {
		if (p_filter != nullptr && std::strstr(entry.name, p_filter) == nullptr) {
			continue;
		}
		g_current = entry.name;
		const int before = g_fails;
		entry.fn();
		ran++;
		std::printf("%s %s\n", g_fails == before ? "ok  " : "FAIL", entry.name);
	}
	std::printf("%d tests, %d checks, %d failures\n", ran, g_checks, g_fails);
	return g_fails == 0 ? 0 : 1;
}

} // namespace slabtest

int main(int p_argc, char **p_argv) {
	return slabtest::run(p_argc > 1 ? p_argv[1] : nullptr);
}
