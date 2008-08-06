include ../common/common.mk

srpm:
	perl Build.PL
	./Build dist
	rpmbuild ${RPMFLAGS} -bs --nodeps perl-TAP-Harness-JUnit.spec
