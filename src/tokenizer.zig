const std = @import("std");
const mem = std.mem;

pub const Token = struct {
    kind: Kind,
    start: usize,
    len: usize,
    raw: []const u8,
    line: usize,
    line_offset: usize,

    pub const Kind = enum {
        // symbols
        hash,
        percent,
        ampersand,
        asterisk,
        left_paren,
        right_paren,
        minus,
        underscore,
        equal,
        left_square,
        right_square,
        left_curly,
        right_curly,
        vertical_bar,
        semi_colon,
        colon,
        comma,
        period,
        greater_than,
        question_mark,

        // alphanumeric
        dec_number,
        hex_number,
        oct_number,
        bin_number,
        identifier,

        // mixed
        string,
        builtin,
        comment,

        invalid,
    };
};

const TokenList = std.ArrayList(Token);

const State = struct {
    source: []const u8,
    line: usize,
    line_start: usize,
    mode: ?Mode,
    mode_start: ?usize,
    tokens: TokenList,

    const Mode = enum {
        builtin,
        comment,
        string,
        identifier,
        dec_number,
        hex_number,
        oct_number,
        bin_number,

        underscore,
    };
};

/// TODO: Expand allowed codepoints to full Unicode range (for the time being it's ASCII only).
pub fn tokenize(allocator: mem.Allocator, source: []const u8) ![]const Token {
    var state = State{
        .source = source,
        .line = 0,
        .line_start = 0,
        .mode = null,
        .mode_start = null,
        .tokens = try TokenList.initCapacity(allocator, source.len / 8),
    };

    for (state.source) |char, i| {
        if (state.mode) |mode| {
            const start = state.mode_start.?;
            const prev_char = state.source[i - 1];
            switch (mode) {
                .builtin => if (isValidIdentifierChar(char))
                    continue
                else
                    try finalize(
                        &state,
                        if (!(i - start > 1))
                            .invalid
                        else
                            .builtin,
                        i,
                    ),
                .comment => switch (char) {
                    '\r', '\n' => {
                        try finalize(&state, .comment, i);
                    },
                    else => continue,
                },
                .string => switch (char) {
                    '"' => {
                        if (prev_char != '\\') {
                            try finalize(&state, .string, i + 1);
                        }
                        continue;
                    },
                    '\r', '\n' => {
                        try finalize(&state, .invalid, i);
                    },
                    else => continue,
                },
                .identifier => if (isValidIdentifierChar(char)) continue else try finalize(&state, .identifier, i),
                .dec_number => {
                    if (i == start + 1) {
                        switch (char) {
                            'x' => {
                                state.mode = .hex_number;
                                continue;
                            },
                            'o' => {
                                state.mode = .oct_number;
                                continue;
                            },
                            'b' => {
                                state.mode = .bin_number;
                                continue;
                            },
                            else => {},
                        }
                    }

                    switch (char) {
                        '0'...'9' => continue,
                        '_' => {
                            if (prev_char == '_') {
                                try finalize(&state, .invalid, i + 1);
                            }
                            continue;
                        },
                        else => try finalize(
                            &state,
                            if (prev_char == '_')
                                .invalid
                            else
                                .dec_number,
                            i,
                        ),
                    }
                },
                .hex_number => {
                    const prev_char_not_number = prev_char == '_' or prev_char == 'x';
                    switch (char) {
                        '0'...'9', 'A'...'F', 'a'...'f' => continue,
                        '_' => {
                            if (prev_char_not_number) {
                                try finalize(&state, .invalid, i + 1);
                            }
                            continue;
                        },
                        else => try finalize(
                            &state,
                            if (prev_char_not_number)
                                .invalid
                            else
                                .hex_number,
                            i,
                        ),
                    }
                },
                .oct_number => {
                    const prev_char_not_number = prev_char == '_' or prev_char == 'o';
                    switch (char) {
                        '0'...'7' => continue,
                        '_' => {
                            if (prev_char_not_number) {
                                try finalize(&state, .invalid, i + 1);
                            }
                            continue;
                        },
                        else => try finalize(
                            &state,
                            if (prev_char_not_number)
                                .invalid
                            else
                                .oct_number,
                            i,
                        ),
                    }
                },
                .bin_number => {
                    const prev_char_not_number = prev_char == '_' or prev_char == 'b';
                    switch (char) {
                        '0', '1' => continue,
                        '_' => {
                            if (prev_char_not_number) {
                                try finalize(&state, .invalid, i + 1);
                            }
                            continue;
                        },
                        else => try finalize(
                            &state,
                            if (prev_char_not_number)
                                .invalid
                            else
                                .bin_number,
                            i,
                        ),
                    }
                },
                .underscore => switch (char) {
                    'A'...'Z', 'a'...'z', '0'...'9', '_' => {
                        state.mode = .identifier;
                        continue;
                    },
                    // consume the previous character (i.e. the underscore character)
                    else => try finalize(&state, .underscore, i),
                },
            }
        }

        if (state.mode != null) {
            @panic("tokenize reached an invalid state where `mode` was unexpectedly not null");
        }

        // there was no `mode` or it was finalized without consuming the character,
        // in either case we still need to process the current character.
        switch (char) {
            // invalid/reserved characters
            '`', '~', '!', '$', '^', '+', '\\', '<', '/' => try consume(&state, .invalid, i),

            // single symbol token characters
            '#' => try consume(&state, .hash, i),
            '%' => try consume(&state, .percent, i),
            '&' => try consume(&state, .ampersand, i),
            '*' => try consume(&state, .asterisk, i),
            '(' => try consume(&state, .left_paren, i),
            ')' => try consume(&state, .right_paren, i),
            '-' => try consume(&state, .minus, i),
            '=' => try consume(&state, .equal, i),
            '[' => try consume(&state, .left_square, i),
            ']' => try consume(&state, .right_square, i),
            '{' => try consume(&state, .left_curly, i),
            '}' => try consume(&state, .right_curly, i),
            '|' => try consume(&state, .vertical_bar, i),
            ';' => try consume(&state, .semi_colon, i),
            ':' => try consume(&state, .colon, i),
            ',' => try consume(&state, .comma, i),
            '.' => try consume(&state, .period, i),
            '>' => try consume(&state, .greater_than, i),
            '?' => try consume(&state, .question_mark, i),

            // mode-setting characters
            '@' => begin(&state, .builtin, i),
            '\'' => begin(&state, .comment, i),
            '"' => begin(&state, .string, i),
            'A'...'Z', 'a'...'z' => begin(&state, .identifier, i),
            '0'...'9' => begin(&state, .dec_number, i),
            '_' => begin(&state, .underscore, i),

            '\r', '\n' => {
                state.line += 1;
                state.line_start = i + 1;
            },
            // everything else is ignored
            // TODO: clear this up if/when need be
            else => {},
        }
    }

    if (state.mode) |mode| {
        const start = state.mode_start.?;
        const end = state.source.len;
        const len = end - start;
        const last_char = state.source[end - 1];
        switch (mode) {
            .builtin => try finalize(
                &state,
                if (!(len > 1))
                    .invalid
                else
                    .builtin,
                end,
            ),
            .comment => try finalize(&state, .comment, end),
            .string => try finalize(
                &state,
                if (!(len > 1) or (last_char != '"') or (state.source[end - 2] == '\\'))
                    .invalid
                else
                    .string,
                end,
            ),
            .identifier => try finalize(&state, .identifier, end),
            .dec_number => try finalize(
                &state,
                if (last_char == '_')
                    .invalid
                else
                    .dec_number,
                end,
            ),
            .hex_number => try finalize(
                &state,
                if (last_char == 'x' or last_char == '_')
                    .invalid
                else
                    .hex_number,
                end,
            ),
            .oct_number => try finalize(
                &state,
                if (last_char == 'o' or last_char == '_')
                    .invalid
                else
                    .oct_number,
                end,
            ),
            .bin_number => try finalize(
                &state,
                if (last_char == 'b' or last_char == '_')
                    .invalid
                else
                    .bin_number,
                end,
            ),
            .underscore => if (len > 1)
                @panic("tokenizer: reached end of source and mode was `underscore` but len was greater than 1.")
            else
                try consume(&state, .underscore, end - 1),
        }
    }

    return state.tokens.toOwnedSlice();
}

inline fn isValidIdentifierChar(char: u8) bool {
    return switch (char) {
        'A'...'Z', 'a'...'z', '0'...'9', '_' => true,
        else => false,
    };
}

inline fn finalize(state: *State, kind: Token.Kind, end: usize) !void {
    try appendToken(state, kind, state.mode_start.?, end);
    state.mode = null;
    state.mode_start = null;
}

inline fn begin(state: *State, mode: State.Mode, start: usize) void {
    if (state.mode != null or state.mode_start != null) {
        @panic("tried to begin a new mode before the current mode was finalized");
    }
    state.mode = mode;
    state.mode_start = start;
}

inline fn consume(state: *State, kind: Token.Kind, at: usize) !void {
    try appendToken(state, kind, at, at + 1);
}

inline fn appendToken(state: *State, kind: Token.Kind, start: usize, end: usize) !void {
    if (!(end > start)) {
        @panic("appendToken received an `end` value that was not greater than `start`");
    }
    if (!(start >= state.line_start)) {
        @panic("appendToken recieved a `start` value that was less than `state.line_start`");
    }
    try state.tokens.append(Token{
        .kind = kind,
        .start = start,
        .len = end - start,
        .raw = state.source[start..end],
        .line = state.line,
        .line_offset = start - state.line_start,
    });
}

test "invalid reserved symbols" {
    try expectTokens("`", &.{.invalid});
    try expectTokens("~", &.{.invalid});
    try expectTokens("!", &.{.invalid});
    try expectTokens("$", &.{.invalid});
    try expectTokens("^", &.{.invalid});
    try expectTokens("+", &.{.invalid});
    try expectTokens("\\", &.{.invalid});
    try expectTokens("<", &.{.invalid});
    try expectTokens("/", &.{.invalid});
}

test "single symbol tokens" {
    try expectTokens("#", &.{.hash});
    try expectTokens("%", &.{.percent});
    try expectTokens("&", &.{.ampersand});
    try expectTokens("*", &.{.asterisk});
    try expectTokens("(", &.{.left_paren});
    try expectTokens(")", &.{.right_paren});
    try expectTokens("-", &.{.minus});
    try expectTokens("_", &.{.underscore});
    try expectTokens("=", &.{.equal});
    try expectTokens("[", &.{.left_square});
    try expectTokens("]", &.{.right_square});
    try expectTokens("{", &.{.left_curly});
    try expectTokens("}", &.{.right_curly});
    try expectTokens("|", &.{.vertical_bar});
    try expectTokens(";", &.{.semi_colon});
    try expectTokens(":", &.{.colon});
    try expectTokens(",", &.{.comma});
    try expectTokens(".", &.{.period});
    try expectTokens(">", &.{.greater_than});
    try expectTokens("?", &.{.question_mark});
}

test "dec_number tokens" {
    try expectTokens("0", &.{.dec_number});
    try expectTokens("09", &.{.dec_number});
    try expectTokens("0_", &.{.invalid});
}

test "hex_number tokens" {
    try expectTokens("0x", &.{.invalid});
    try expectTokens("0x_", &.{.invalid});
    try expectTokens("0x_0", &.{ .invalid, .dec_number });
    try expectTokens("0x0_", &.{.invalid});
    try expectTokens("0x0", &.{.hex_number});
    try expectTokens("0x0123456789ABCDEF", &.{.hex_number});
    try expectTokens("0x0_9_A_F", &.{.hex_number});
}

test "oct_number tokens" {
    try expectTokens("0o", &.{.invalid});
    try expectTokens("0o_", &.{.invalid});
    try expectTokens("0o_0", &.{ .invalid, .dec_number });
    try expectTokens("0o0_", &.{.invalid});
    try expectTokens("0o8", &.{ .invalid, .dec_number });
    try expectTokens("0o9", &.{ .invalid, .dec_number });
    try expectTokens("0o0", &.{.oct_number});
    try expectTokens("0o01234567", &.{.oct_number});
    try expectTokens("0o0_7", &.{.oct_number});
}

test "bin_number tokens" {
    try expectTokens("0b", &.{.invalid});
    try expectTokens("0b_", &.{.invalid});
    try expectTokens("0b_0", &.{ .invalid, .dec_number });
    try expectTokens("0b0_", &.{.invalid});
    try expectTokens("0b2", &.{ .invalid, .dec_number });
    try expectTokens("0b3", &.{ .invalid, .dec_number });
    try expectTokens("0b4", &.{ .invalid, .dec_number });
    try expectTokens("0b5", &.{ .invalid, .dec_number });
    try expectTokens("0b6", &.{ .invalid, .dec_number });
    try expectTokens("0b7", &.{ .invalid, .dec_number });
    try expectTokens("0b8", &.{ .invalid, .dec_number });
    try expectTokens("0b9", &.{ .invalid, .dec_number });
    try expectTokens("0b01", &.{.bin_number});
    try expectTokens("0b0_1", &.{.bin_number});
}

test "identifier tokens" {
    // all sequences starting with an alpha character are valid identifiers
    var i: u8 = 'A';
    while (i <= 'Z') : (i += 1) {
        try expectTokens(&.{i}, &.{.identifier});
    }
    i = 'a';
    while (i <= 'z') : (i += 1) {
        try expectTokens(&.{i}, &.{.identifier});
    }

    // can't start an identifier with a number
    try expectTokens("0a", &.{ .dec_number, .identifier });
    try expectTokens("a0", &.{.identifier});

    // underscores in identifiers are valid
    try expectTokens("_0", &.{.identifier});
    try expectTokens("__AZaz09__", &.{.identifier});
}

test "string tokens" {
    try expectTokens("\"", &.{.invalid}); // double quote without a closing quote is treated as invalid
    try expectTokens("\"some string value that's invalid because it's missing the closing quote", &.{.invalid});
    try expectTokens("\"string value\"", &.{.string});
    try expectTokens("\"line one\"\n\"line two\"", &.{ .string, .string });
}

test "builtin tokens" {
    try expectTokens("@", &.{.invalid});
    try expectTokens("@0asdf", &.{.builtin});
    try expectTokens("@asdf0", &.{.builtin});
    try expectTokens("@_asdf", &.{.builtin});
}

test "comment tokens" {
    try expectTokens("'", &.{.comment});
    try expectTokens("''", &.{.comment});
    try expectTokens("' some regular comment", &.{.comment});
}

test "comprehensive" {
    try expectTokens(
        \\'' doc comment
        \\
        \\:= --::some_lib
        \\:= -::some_internal_module
        \\:= _::some_child_module
        \\
        \\' comment about where and how c lib is packaged or something
        \\c := --::some_c_lib
        \\
        \\-- ProductType := &{
        \\    -- internal_product_type: &{
        \\    },
        \\    -- internal_sum_type: |{
        \\    },
        \\    -- internal_enum_type: ;{
        \\    },
        \\    - internal_indexed_type: []@some_builtin_indexer(ElementType),
        \\    - internal_indexed_type2: []@some_builtin_indexer(&{
        \\        - some_field: @some_type,
        \\    }),
        \\}
        \\
        \\-- some_parameterized_code_block := (
        \\      first: @conditional,
        \\      second: some_lib::SomeType,
        \\      third: @primitive,
        \\) ReturnType {
        \\
        \\    ' assuming first is a branching/conditional primitive
        \\    ? first {
        \\        %first {
        \\          @someLoggingOperation("went from {} to {}", %first, first)
        \\        }
        \\
        \\        :some_parameterized_code_block ReturnType{}
        \\    } : {
        \\        @someLoggingOperation("second 'false'")
        \\    }
        \\
        \\    'assuming second is a sum type
        \\    |second| -> {
        \\        |SomeType::Opt1(value: Opt1Value)| {
        \\            @someLoggingOperation("value: {}", value)
        \\        },
        \\
        \\        |SomeType::Opt2(v1: Opt2V1, v2: Opt2V2)| {
        \\            @someLoggingOperation("value: {}, {}", v1, v2)
        \\        }
        \\    } : {
        \\        @someLoggingOperation("did not match any values")
        \\    }
        \\
        \\    some_local := @range(0, 0xA)
        \\    (some_local) => (i: @rangeInt) {
        \\        @someLoggingOperation("{}", (third @plus i))
        \\    }
        \\
        \\    :some_parameterized_code_block ReturnType{}
        \\}
    , &.{
        .comment, //
        //
        .colon, .equal, .minus, .minus, .colon, .colon, .identifier, // some_lib
        .colon, .equal, .minus, .colon, .colon, .identifier, // some_internal_module
        .colon, .equal, .underscore, .colon, .colon, .identifier, // some_child_module
        //
        .comment, //
        .identifier, .colon, .equal, .minus, .minus, .colon, .colon, .identifier, // some_c_lib
        //
        .minus, .minus, .identifier, .colon, .equal, .ampersand, .left_curly, // ProductType
        .minus, .minus, .identifier, .colon, .ampersand, .left_curly, // internal_product_type
        .right_curly, .comma, //
        .minus, .minus, .identifier, .colon, .vertical_bar, .left_curly, // internal_sum_type
        .right_curly, .comma, //
        .minus, .minus, .identifier, .colon, .semi_colon, .left_curly, // internal_enum_type
        .right_curly, .comma, //
        .minus, .identifier, .colon, .left_square, .right_square, .builtin, .left_paren, .identifier, .right_paren, //-
        .comma, // internal_indexed_type
        .minus, .identifier, .colon, .left_square, .right_square, .builtin, .left_paren, .ampersand, //-
        .left_curly, // internal_indexed_type2
        .minus, .identifier, .colon, .builtin, .comma, // some_field
        .right_curly, .right_paren, .comma, //
        .right_curly, //
        //
        .minus, .minus, .identifier, .colon, .equal, .left_paren, // some_parameterized_code_block
        .identifier, .colon, .builtin, .comma, // first
        .identifier, .colon, .identifier, .colon, .colon, .identifier, .comma, // second
        .identifier, .colon, .builtin, .comma, // third
        .right_paren, .identifier, .left_curly, // ReturnType
        //
        .comment, //
        .question_mark, .identifier, .left_curly, // ?
        .percent, .identifier, .left_curly, // %
        .builtin, .left_paren, .string, .comma, .percent, .identifier, .comma, .identifier, .right_paren, //
        .right_curly, //
        //
        .colon, .identifier, .identifier, .left_curly, .right_curly, // :some_parameterized_code_block
        .right_curly, .colon, .left_curly, //
        .builtin, .left_paren, .string, .right_paren, // @someLogginOperation
        .right_curly, //
        //
        .comment, //
        .vertical_bar, .identifier, .vertical_bar, .minus, .greater_than, .left_curly, // |second|
        .vertical_bar, .identifier, .colon, .colon, .identifier, .left_paren, .identifier, .colon, .identifier, //-
        .right_paren, .vertical_bar, .left_curly, // Opt1
        .builtin, .left_paren, .string, .comma, .identifier, .right_paren, //
        .right_curly, .comma, //
        //
        .vertical_bar, .identifier, .colon, .colon, .identifier, .left_paren, .identifier, .colon, .identifier, .comma, //-
        .identifier, .colon, .identifier, .right_paren, .vertical_bar, .left_curly, // Opt2
        .builtin, .left_paren, .string, .comma, .identifier, .comma, .identifier, .right_paren, //
        .right_curly, //
        .right_curly, .colon, .left_curly, //
        .builtin, .left_paren, .string, .right_paren, //
        .right_curly, //
        //
        .identifier, .colon, .equal, .builtin, .left_paren, .dec_number, .comma, .hex_number, .right_paren, // some_local
        .left_paren, .identifier, .right_paren, .equal, .greater_than, .left_paren, .identifier, .colon, .builtin, //-
        .right_paren, .left_curly, // =>
        .builtin, .left_paren, .string, .comma, .left_paren, .identifier, .builtin, .identifier, .right_paren, //-
        .right_paren, //
        .right_curly, //
        //
        .colon, .identifier, .identifier, .left_curly, .right_curly, // :some_parameterized_code_block
        .right_curly, //
    });
}

const print = std.debug.print;
const testing = std.testing;
fn expectTokens(source: []const u8, expected: []const Token.Kind) !void {
    const result = try tokenize(testing.allocator, source);
    defer testing.allocator.free(result);

    testing.expectEqual(result.len, expected.len) catch {
        diffResultVsExpected(result, expected);
        unreachable;
    };

    for (result) |token, i| {
        testing.expectEqual(token.kind, expected[i]) catch {
            diffResultVsExpected(result, expected);
            unreachable;
        };
    }
}

fn diffResultVsExpected(result: []const Token, expected: []const Token.Kind) void {
    print("\n", .{});

    var i: usize = 0;
    var prev_line: usize = 1;
    while (i < @maximum(result.len, expected.len)) : (i += 1) {
        const token = if (i < result.len) result[i] else null;
        if (token) |t| {
            if (t.line != prev_line) {
                print("\n", .{});
                prev_line = t.line;
            }
        }

        if (i < expected.len) {
            print("expected: {s}, ", .{@tagName(expected[i])});
        } else {
            print("didn't expect anything, ", .{});
        }

        if (token) |t| {
            print("got: {s} at line {d} column {d}.\n", .{ @tagName(t.kind), t.line, t.line_offset });
        } else {
            print("didn't get anything.\n", .{});
        }
    }

    print("\n", .{});
}
