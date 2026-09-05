#pragma once

namespace slabtest {

using TestFn = void (*)();

int register_test(const char *p_name, TestFn p_fn);
void expect(bool p_ok, const char *p_what);
void expect_near(double p_got, double p_want, double p_tol, const char *p_what);
void expect_eq(long long p_got, long long p_want, const char *p_what);
int run(const char *p_filter);

} // namespace slabtest

#define SLAB_TEST(name)                                                      \
	static void name();                                                      \
	static const int slab_reg_##name = slabtest::register_test(#name, name); \
	static void name()
