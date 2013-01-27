TAP::Harness::JUnit
===================

[TAP::Harness::JUnit][1] provides a test harness that runs [TAP][5] tests and outputs JUnit-compatible XML.

It is useful for integrating Perl test suites with software that expects JUnit output, for example [Jenkins][3].

## Use

To generate JUnit output using prove, supply `TAP::Harness::JUnit` for the `--harness` argument to `prove`:

```sh
prove --harness TAP::Harness::JUnit
```

## Environment variables

`JUNIT_OUTPUT_FILE` - specify the name of the JUnit XML output file.  Defaults to `junit_output.xml`.

`JUNIT_PACKAGE` - specify a package name for the results.


## Installation

Before building it yourself, you may prefer to fetch the package from your
Operating System distribution, if one exists. Here's how would you install
it in Fedora:

```sh
yum -y install 'perl(TAP::Harness::JUnit)'
```

Otherwise, follow the usual [Module::Build][4] convention:

```sh
perl Build.pl
./Build
./Build install
```

The build script will issue a warning when any of required modules is missing or wrong version.

See the [POD documentation][2] for more information (on how to use the module, licensing, copyright, etc.):

```sh
perldoc TAP::Harness::JUnit
```

Before installing the module, you can do:

```sh
perldoc lib/TAP/Harness/JUnit.pm
```


[1]: http://search.cpan.org/dist/TAP-Harness-JUnit/ "TAP::Harness::JUnit"
[2]: http://search.cpan.org/dist/TAP-Harness-JUnit/lib/TAP/Harness/JUnit.pm "TAP::Harness::JUnit POD"
[3]: http://jenkins-ci.org "Jenkins"
[4]: http://search.cpan.org/dist/Module-Build/lib/Module/Build.pm "Module::Build POD"
[5]: http://testanything.org "TAP - Test Anything Protocol"
