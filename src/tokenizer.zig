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
        // single symbol tokens
        tick,
        tilde,
        exclamation,
        dollar,
        percent,
        caret,
        ampersand,
        asterisk,
        left_paren,
        right_paren,
        minus,
        underscore,
        equal,
        plus,
        left_square,
        right_square,
        left_curly,
        right_curly,
        back_slash,
        vertical_bar,
        semi_colon,
        colon,
        comma,
        period,
        less_than,
        greater_than,
        forward_slash,
        question_mark,

        // multiple symbol tokens
        hash_question_mark,
        ampersand_left_curly,
        minus_minus,
        minus_greater_than,
        equal_greater_than,
        vertical_bar_left_curly,
        semi_colon_left_curly,
        colon_colon,
        colon_equal,
        period_period,

        // literal tokens
        dec_number,
        hex_number,
        oct_number,
        bin_number,
        string,

        // identifier tokens
        builtin,
        identifier,
        hash_identifier,

        // comment tokens
        comment,
        doc_comment,

        invalid,
    };
};

const TokenList = std.ArrayList(Token);

const State = struct {
    in: []const u8,
    mode: Mode,
    start: ?usize,
    out: TokenList,
    line: usize,
    line_start: usize,

    const Mode = enum {
        hash,
        ampersand,
        minus,
        underscore,
        equal,
        vertical_bar,
        semi_colon,
        colon,
        period,
        dec_number,
        hex_number,
        oct_number,
        bin_number,
        string,
        builtin,
        identifier,
        hash_identifier,
        comment,
        doc_comment,
        invalid,
        none,
    };
};

/// TODO: Expand allowed codepoints to full Unicode range (for the time being it's ASCII only).
pub fn tokenize(allocator: mem.Allocator, source: []const u8) ![]const Token {
    var state = State{
        .in = source,
        .mode = .none,
        .start = null,
        .out = try TokenList.initCapacity(allocator, source.len / 8),
        .line = 1,
        .line_start = 0,
    };

    for (state.in) |_, i| {
        try switch (state.mode) {
            .hash => nextHash(&state, i),
            .ampersand => nextAmpersand(&state, i),
            .minus => nextMinus(&state, i),
            .underscore => nextUnderscore(&state, i),
            .equal => nextEqual(&state, i),
            .vertical_bar => nextVerticalBar(&state, i),
            .semi_colon => nextSemiColon(&state, i),
            .colon => nextColon(&state, i),
            .period => nextPeriod(&state, i),
            .dec_number => nextDecNumber(&state, i),
            .hex_number => nextHexNumber(&state, i),
            .oct_number => nextOctNumber(&state, i),
            .bin_number => nextBinNumber(&state, i),
            .string => nextString(&state, i),
            .builtin => nextBuiltin(&state, i),
            .identifier => nextIdentifier(&state, i),
            .hash_identifier => nextHashIdentifier(&state, i),
            .comment => nextComment(&state, i),
            .doc_comment => nextDocComment(&state, i),
            .invalid, .none => nextInvalidOrNone(&state, i),
        };
    }

    if (state.mode == .none) {
        return state.out.toOwnedSlice();
    }

    const last_char = state.in[state.in.len - 1];
    const last_token_len = state.in.len - state.start.?;
    switch (state.mode) {
        .hash => try consumeStartToEnd(&state, .invalid),
        .ampersand => try consumeStartToEnd(&state, .ampersand),
        .minus => try consumeStartToEnd(&state, .minus),
        .underscore => try consumeStartToEnd(&state, .underscore),
        .equal => try consumeStartToEnd(&state, .equal),
        .vertical_bar => try consumeStartToEnd(&state, .vertical_bar),
        .semi_colon => try consumeStartToEnd(&state, .semi_colon),
        .colon => try consumeStartToEnd(&state, .colon),
        .period => try consumeStartToEnd(&state, .period),
        .dec_number => {
            if (isValidDecNumberEnd(last_char)) {
                try consumeStartToEnd(&state, .dec_number);
            } else {
                try consumeStartToEnd(&state, .invalid);
            }
        },
        .hex_number, .oct_number, .bin_number => {
            if (isValidSpecialNumberEnd(last_char, last_token_len)) {
                try consumeStartToEnd(
                    &state,
                    switch (state.mode) {
                        .hex_number => .hex_number,
                        .oct_number => .oct_number,
                        .bin_number => .bin_number,
                        else => unreachable,
                    },
                );
            } else {
                try consumeStartToEnd(&state, .invalid);
            }
        },
        .string => try consumeStartToEnd(&state, .invalid),
        .builtin => {
            if (isValidBuiltinLen(last_token_len)) {
                try consumeStartToEnd(&state, .builtin);
            } else {
                try consumeStartToEnd(&state, .invalid);
            }
        },
        .identifier => try consumeStartToEnd(&state, .identifier),
        .hash_identifier => try consumeStartToEnd(&state, .hash_identifier),
        .comment => {
            if (isValidCommentLen(last_token_len)) {
                try consumeStartToEnd(&state, .comment);
            } else {
                try consumeStartToEnd(&state, .invalid);
            }
        },
        .doc_comment => {
            if (isValidDocCommentLen(last_token_len)) {
                try consumeStartToEnd(&state, .doc_comment);
            } else {
                try consumeStartToEnd(&state, .invalid);
            }
        },
        .invalid => try consumeStartToEnd(&state, .invalid),
        .none => unreachable,
    }

    return state.out.toOwnedSlice();
}

inline fn nextHash(state: *State, i: usize) !void {
    const char = state.in[i];
    if (char == '?') {
        try consumeStartIncl(state, .hash_question_mark, i);
    } else if (isValidIdentifierChar(char)) {
        state.mode = .hash_identifier;
    } else {
        try consumeStartExcl(state, .invalid, i);
    }
}

inline fn nextAmpersand(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '{' => {
            try consumeStartIncl(state, .ampersand_left_curly, i);
        },
        else => {
            try consumeStartExcl(state, .ampersand, i);
        },
    }
}

inline fn nextMinus(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '-' => {
            try consumeStartIncl(state, .minus_minus, i);
        },
        else => {
            try consumeStartExcl(state, .minus, i);
        },
    }
}

inline fn nextUnderscore(state: *State, i: usize) !void {
    switch (state.in[i]) {
        'A'...'Z', 'a'...'z' => {
            state.mode = .identifier;
        },
        else => {
            try consumeStartExcl(state, .underscore, i);
        },
    }
}

inline fn nextEqual(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '>' => {
            try consumeStartIncl(state, .equal_greater_than, i);
        },
        else => {
            try consumeStartExcl(state, .equal, i);
        },
    }
}

inline fn nextVerticalBar(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '{' => {
            try consumeStartIncl(state, .vertical_bar_left_curly, i);
        },
        else => {
            try consumeStartExcl(state, .vertical_bar, i);
        },
    }
}

inline fn nextSemiColon(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '{' => {
            try consumeStartIncl(state, .semi_colon_left_curly, i);
        },
        else => {
            try consumeStartExcl(state, .semi_colon, i);
        },
    }
}

inline fn nextColon(state: *State, i: usize) !void {
    switch (state.in[i]) {
        ':' => {
            try consumeStartIncl(state, .colon_colon, i);
        },
        '=' => {
            try consumeStartIncl(state, .colon_equal, i);
        },
        else => {
            try consumeStartExcl(state, .colon, i);
        },
    }
}

inline fn nextPeriod(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '.' => {
            try consumeStartIncl(state, .period_period, i);
        },
        else => {
            try consumeStartExcl(state, .period, i);
        },
    }
}

inline fn nextDecNumber(state: *State, i: usize) !void {
    switch (state.in[i]) {
        'x', 'o', 'b' => {
            if (i != (state.start.? + 1)) {
                try consumeStartIncl(state, .invalid, i);
            } else switch (state.in[i]) {
                'x' => {
                    state.mode = .hex_number;
                },
                'o' => {
                    state.mode = .oct_number;
                },
                'b' => {
                    state.mode = .bin_number;
                },
                else => unreachable,
            }
        },
        '0'...'9' => {
            // valid, nothing to check for here
        },
        '_' => {
            if (state.in[i - 1] == '_') {
                try consumeStartIncl(state, .invalid, i);
            }
        },
        else => {
            if (isValidDecNumberEnd(state.in[i - 1])) {
                try consumeStartExcl(state, .dec_number, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
    }
}

inline fn isValidDecNumberEnd(char: u8) bool {
    return char != '_';
}

inline fn nextHexNumber(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '0'...'9', 'A'...'F', 'a'...'f' => {
            // keep going to next char
        },
        '_' => {
            switch (state.in[i - 1]) {
                'x', '_' => {
                    try consumeStartIncl(state, .invalid, i);
                },
                else => {
                    // keep it going
                },
            }
        },
        else => {
            if (isValidSpecialNumberEnd(state.in[i - 1], i - state.start.?)) {
                try consumeStartExcl(state, .hex_number, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
    }
}

inline fn nextOctNumber(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '0'...'7' => {
            // keep going to next char
        },
        '_' => {
            switch (state.in[i - 1]) {
                'o', '_' => {
                    try consumeStartIncl(state, .invalid, i);
                },
                else => {
                    // keep it going
                },
            }
        },
        else => {
            if (isValidSpecialNumberEnd(state.in[i - 1], i - state.start.?)) {
                try consumeStartExcl(state, .oct_number, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
    }
}

inline fn nextBinNumber(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '0', '1' => {
            // keep going to next char
        },
        '_' => {
            switch (state.in[i - 1]) {
                'b', '_' => {
                    try consumeStartIncl(state, .invalid, i);
                },
                else => {
                    // keep it going
                },
            }
        },
        else => {
            if (isValidSpecialNumberEnd(state.in[i - 1], i - state.start.?)) {
                try consumeStartExcl(state, .bin_number, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
    }
}

inline fn isValidSpecialNumberEnd(char: u8, token_len: usize) bool {
    if (token_len < 3)
        return false;

    return char != '_';
}

inline fn nextString(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '"' => if (state.in[i - 1] != '\\') {
            // this is an unescaped closing quote
            try consumeStartIncl(state, .string, i);
        },
        '\n' => {
            // a newline char was reached before the closing quote which is invalid
            try consumeStartIncl(state, .invalid, i);
        },
        else => {
            // TODO: everything else valid?
        },
    }
}

inline fn nextBuiltin(state: *State, i: usize) !void {
    switch (state.in[i]) {
        'A'...'Z', 'a'...'z', '0'...'9', '_' => {
            // keep it going
        },
        else => {
            if (isValidBuiltinLen(i - state.start.?)) {
                try consumeStartExcl(state, .builtin, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
    }
}

inline fn isValidBuiltinLen(len: usize) bool {
    return len >= 2;
}

inline fn nextIdentifier(state: *State, i: usize) !void {
    if (!isValidIdentifierChar(state.in[i])) {
        try consumeStartExcl(state, .identifier, i);
    }
}

inline fn nextHashIdentifier(state: *State, i: usize) !void {
    if (!isValidIdentifierChar(state.in[i])) {
        try consumeStartExcl(state, .hash_identifier, i);
    }
}

inline fn isValidIdentifierChar(char: u8) bool {
    return switch (char) {
        'A'...'Z', 'a'...'z', '0'...'9', '_' => true,
        else => false,
    };
}

inline fn nextComment(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '\'' => {
            if (i == (state.start.? + 1)) {
                state.mode = .doc_comment;
            }
        },
        '\n' => {
            if (isValidCommentLen(i - state.start.?)) {
                try consumeStartExcl(state, .comment, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
        else => {
            // everything else valid
        },
    }
}

inline fn isValidCommentLen(len: usize) bool {
    return len >= 2;
}

inline fn nextDocComment(state: *State, i: usize) !void {
    switch (state.in[i]) {
        '\n' => {
            if (isValidDocCommentLen(i - state.start.?)) {
                try consumeStartExcl(state, .doc_comment, i);
            } else {
                try consumeStartExcl(state, .invalid, i);
            }
        },
        else => {
            // everything else valid
        },
    }
}

inline fn isValidDocCommentLen(len: usize) bool {
    return len >= 3;
}

fn nextInvalidOrNone(state: *State, i: usize) !void {
    var new_mode: ?State.Mode = null;
    var new_token: ?Token.Kind = null;
    var new_line: bool = false;
    switch (state.in[i]) {
        '`' => new_token = .tick,
        '~' => new_token = .tilde,
        '!' => new_token = .exclamation,
        '@' => new_mode = .builtin,
        '#' => new_mode = .hash,
        '$' => new_token = .dollar,
        '%' => new_token = .percent,
        '^' => new_token = .caret,
        '&' => new_mode = .ampersand,
        '*' => new_token = .asterisk,
        '(' => new_token = .left_paren,
        ')' => new_token = .right_paren,
        '-' => new_mode = .minus,
        '_' => new_mode = .underscore,
        '=' => new_mode = .equal,
        '+' => new_token = .plus,
        '[' => new_token = .left_square,
        ']' => new_token = .right_square,
        '{' => new_token = .left_curly,
        '}' => new_token = .right_curly,
        '\\' => new_token = .back_slash,
        '|' => new_mode = .vertical_bar,
        ';' => new_mode = .semi_colon,
        ':' => new_mode = .colon,
        '\'' => new_mode = .comment,
        '"' => new_mode = .string,
        ',' => new_token = .comma,
        '.' => new_mode = .period,
        '<' => new_token = .less_than,
        '>' => new_token = .greater_than,
        '/' => new_token = .forward_slash,
        '?' => new_token = .question_mark,
        '0'...'9' => new_mode = .dec_number,
        'A'...'Z', 'a'...'z' => new_mode = .identifier,
        ' ', '\t' => new_mode = .none,
        '\n', '\r' => {
            new_mode = .none;
            new_line = true;
        },
        else => new_mode = .invalid,
    }

    const old_mode = state.mode;
    const old_start = state.start;

    if (new_mode) |nm| {
        if (nm != old_mode) {
            state.mode = nm;
            state.start = i;
        } else if (old_mode == .invalid) {
            return;
        }
    } else if (new_token) |nt| {
        try appendToken(state, nt, i, i + 1);
        state.mode = .none;
    }

    if (old_mode == .invalid) {
        try appendToken(state, .invalid, old_start.?, i);
    }

    if (new_line) {
        state.line += 1;
        state.line_start = i + 1;
    }
}

inline fn consumeStartIncl(state: *State, kind: Token.Kind, i: usize) !void {
    try appendToken(state, kind, state.start.?, i + 1);
    state.mode = .none;
    state.start = null;
}

inline fn consumeStartExcl(state: *State, kind: Token.Kind, i: usize) !void {
    try appendToken(state, kind, state.start.?, i);
    state.mode = .none;
    state.start = null;
    // the char at `i` wasn't consumed so we still have to process it.
    try nextInvalidOrNone(state, i);
}

inline fn consumeStartToEnd(state: *State, kind: Token.Kind) !void {
    try appendToken(state, kind, state.start.?, state.in.len);
}

inline fn appendToken(state: *State, kind: Token.Kind, start: usize, end: usize) !void {
    if (!(end > start)) {
        @panic("appendToken received an `end` value that was not greater than `start`");
    }
    if (!(start >= state.line_start)) {
        @panic("appendToken recieved a `start` value that was less than `state.line_start`");
    }
    try state.out.append(Token{
        .kind = kind,
        .start = start,
        .len = end - start,
        .raw = state.in[start..end],
        .line = state.line,
        .line_offset = start - state.line_start,
    });
}

// not all of the symbols have been assigned, but they are still reserved by the language so we make sure here that the
// tokenizer can handle them, because not all of them will show up in the 'comprehensive' test.
test "all symbols" {
    try expectTokens("`", &.{.tick});
    try expectTokens("~", &.{.tilde});
    try expectTokens("!", &.{.exclamation});
    try expectTokens("@", &.{.invalid});
    try expectTokens("#", &.{.invalid});
    try expectTokens("$", &.{.dollar});
    try expectTokens("%", &.{.percent});
    try expectTokens("^", &.{.caret});
    try expectTokens("&", &.{.ampersand});
    try expectTokens("*", &.{.asterisk});
    try expectTokens("(", &.{.left_paren});
    try expectTokens(")", &.{.right_paren});
    try expectTokens("-", &.{.minus});
    try expectTokens("_", &.{.underscore});
    try expectTokens("=", &.{.equal});
    try expectTokens("+", &.{.plus});
    try expectTokens("[", &.{.left_square});
    try expectTokens("]", &.{.right_square});
    try expectTokens("{", &.{.left_curly});
    try expectTokens("}", &.{.right_curly});
    try expectTokens("\\", &.{.back_slash});
    try expectTokens("|", &.{.vertical_bar});
    try expectTokens(";", &.{.semi_colon});
    try expectTokens(":", &.{.colon});
    try expectTokens("'", &.{.invalid});
    try expectTokens("\"", &.{.invalid});
    try expectTokens(",", &.{.comma});
    try expectTokens(".", &.{.period});
    try expectTokens("<", &.{.less_than});
    try expectTokens(">", &.{.greater_than});
    try expectTokens("/", &.{.forward_slash});
    try expectTokens("?", &.{.question_mark});
}

test "comprehensive" {
    const source =
        \\'' Comprehensive source that includes all current language features
        \\
        \\:= --::std
        \\:= -::json
        \\:= _::commands
        \\
        \\-- ServiceConfig := &{
        \\    -- endpoint: @str,
        \\}
        \\
        \\-- system := (enabled: @bool, config: ServiceConfig) {
        \\    ' builtin print
        \\    @print("Hello World")
        \\}
    ;

    const expected = &.{
        .doc_comment,

        .colon_equal,
        .minus_minus,
        .colon_colon,
        .identifier,

        .minus_minus,
        .identifier,
        .colon_equal,
        .left_parent,
        .right_paren,
        .left_curly,

        .comment,

        .builtin,
        .left_paren,
        .string,
        .right_paren,

        .right_curly,
    };

    try expectTokens(source, expected);
}

const print = std.debug.print;
const testing = std.testing;
fn expectTokens(source: []const u8, expected: []const Token.Kind) !void {
    const tokens = try tokenize(testing.allocator, source);
    defer testing.allocator.free(tokens);

    testing.expectEqual(tokens.len, expected.len) catch {
        print("expectTokens tokens.len != expected.len", .{});
        unreachable;
    };

    for (tokens) |token, i| {
        testing.expectEqual(token.kind, expected[i]) catch {
            print("\nexpectTokens()\nexpected: {s},\ngot: {s} at line {d} col {d}\n\n", .{
                @tagName(expected[i]),
                @tagName(token.kind),
                token.line,
                token.line_offset,
            });
            unreachable;
        };
    }
}
