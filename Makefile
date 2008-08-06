include ../common/common.mk

TARGET=gdc-tools

srpm:
	perl Build.PL
	./Build dist
	rpmbuild ${RPMFLAGS} -bs --nodeps perl-TAP-Harness-JUnit.spec
