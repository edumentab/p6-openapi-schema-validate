class X::OpenAPI::Schema::Validate::BadSchema is Exception {
    has $.path;
    has $.reason;
    method message() {
        "Schema invalid at $!path: $!reason"
    }
}
class X::OpenAPI::Schema::Validate::Failed is Exception {
    has $.path;
    has $.reason;
    method message() {
        "Validation failed for $!path: $!reason"
    }
}

class OpenAPI::Schema::Validate {
    # We'll turn a schema into a tree of Check objects that enforce the
    # various bits of validation.
    my role Check {
        # Path is used for error reporting.
        has $.path;

        # Does the checking; throws if there's a problem.
        method check($value --> Nil) { ... }
    }

    # Check implement the various properties. Per the RFC draft:
    #   Validation keywords typically operate independent of each other,
    #   without affecting each other.
    # Thus we implement them in that way for now, though it does lead to
    # some duplicate type checks.

    my class AllCheck does Check {
        has @.checks;
        method check($value --> Nil) {
            .check($value) for @!checks;
        }
    }

    my class StringCheck does Check {
        method check($value --> Nil) {
            unless $value ~~ Str && $value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason('Not a string');
            }
        }
    }

    my class NumberCheck does Check {
        method check($value --> Nil) {
            unless $value ~~ Real && $value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason('Not a number');
            }
        }
    }

    my class IntegerCheck does Check {
        method check($value --> Nil) {
            unless $value ~~ Int && $value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason('Not an integer');
            }
        }
    }

    my class BooleanCheck does Check {
        method check($value --> Nil) {
            unless $value ~~ Bool && $value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason('Not a boolean');
            }
        }
    }

    my class ArrayCheck does Check {
        method check($value --> Nil) {
            unless $value ~~ Positional && $value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason('Not an array');
            }
        }
    }

    my class ObjectCheck does Check {
        method check($value --> Nil) {
            unless $value ~~ Associative && $value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason('Not an object');
            }
        }
    }

    my class MultipleOfCheck does Check {
        has UInt $.multi;
        method check($value --> Nil) {
            if $value !~~ UInt || !$value.defined {
                die X::OpenAPI::Schema::Validate::Failed.new(:$!path, :reason('Value must be a positive integer'));
            }
            unless $value %% $!multi {
                die X::OpenAPI::Schema::Validate::Failed.new(:$!path, :reason("Integer is not multiple of $!multi"));
            }
        }
    }

    my class MinLengthCheck does Check {
        has Int $.min;
        method check($value --> Nil) {
            if $value ~~ Str && $value.defined && $value.codes < $!min {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason("String less than $!min codepoints");
            }
        }
    }

    my class MaxLengthCheck does Check {
        has Int $.max;
        method check($value --> Nil) {
            if $value ~~ Str && $value.defined && $value.codes > $!max {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason("String more than $!max codepoints");
            }
        }
    }

    my class MaximumCheck does Check {
        has Int $.max;
        has Bool $.exclusive;
        method check($value --> Nil) {
            unless $value ~~ Int && $!exclusive && $value < $!max || !$!exclusive && $value <= $!max {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason("Number is less than $!max");
            }
        }
    }

    my class MinimumCheck does Check {
        has Int $.min;
        has Bool $.exclusive;
        method check($value --> Nil) {
            unless $value ~~ Int && $!exclusive && $value > $!min || !$!exclusive && $value >= $!min {
                die X::OpenAPI::Schema::Validate::Failed.new:
                    :$!path, :reason("Number is more than $!min");
            }
        }
    }

    has Check $!check;

    submethod BUILD(:%schema! --> Nil) {
        $!check = check-for('root', %schema);
    }

    sub check-for($path, %schema) {
        my @checks;

        with %schema<type> {
            when Str {
                when 'string' {
                    push @checks, StringCheck.new(:$path);
                }
                when 'number' {
                    push @checks, NumberCheck.new(:$path);
                }
                when 'integer' {
                    push @checks, IntegerCheck.new(:$path);
                }
                when 'boolean' {
                    push @checks, BooleanCheck.new(:$path);
                }
                when 'array' {
                    push @checks, ArrayCheck.new(:$path);
                }
                when 'object' {
                    push @checks, ObjectCheck.new(:$path);
                }
                default {
                    die X::OpenAPI::Schema::Validate::BadSchema.new:
                        :$path, :reason("Unrecognized type '$_'");
                }
            }
            default {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                    :$path, :reason("The type property must be a string");
            }
        }

        with %schema<multipleOf> {
            when UInt {
                push @checks, MultipleOfCheck.new(:$path, multi => $_);
            }
            default {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                    :$path, :reason("The multipleOf property must be a non-negative integer");
            }
        }

        with %schema<maximum> {
            when Int {
                push @checks, MaximumCheck.new(:$path, max => $_,
                    exclusive => %schema<exclusiveMaximum> // False);
            }
            default {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                    :$path, :reason("The maximum property must be an integer");
            }
        }

        with %schema<exclusiveMaximum> {
            when $_ !~~ Bool {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                     :$path, :reason("The exclusiveMaximum property must be a boolean");
            }
        }

        with %schema<minimum> {
            when Int {
                push @checks, MinimumCheck.new(:$path, min => $_,
                    exclusive => %schema<exclusiveMinimum> // False);
            }
            default {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                     :$path, :reason("The minimum property must be an integer");
            }
        }

        with %schema<exclusiveMinimum> {
            when $_ !~~ Bool {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                     :$path, :reason("The exclusiveMinimum property must be a boolean");
            }
        }

        with %schema<minLength> {
            when UInt {
                push @checks, MinLengthCheck.new(:$path, :min($_));
            }
            default {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                    :$path, :reason("The minLength property must be a non-negative integer");
            }
        }

        with %schema<maxLength> {
            when UInt {
                push @checks, MaxLengthCheck.new(:$path, :max($_));
            }
            default {
                die X::OpenAPI::Schema::Validate::BadSchema.new:
                    :$path, :reason("The maxLength property must be a non-negative integer");
            }
        }

        return @checks == 1 ?? @checks[0] !! AllCheck.new(:@checks);
    }

    method validate($value --> True) {
        $!check.check($value);
        CATCH {
            when X::OpenAPI::Schema::Validate::Failed {
                fail $_;
            }
        }
    }
}