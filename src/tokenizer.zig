const std = @import("std");
const mem = std.mem;

pub const Token = struct {
    kind: Kind,
    start: usize,
    len: usize,
    raw: []const u8,

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
        number,
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
    source: []const u8,
    curr: enum {
        hash,
        ampersand,
        minus,
        underscore,
        equal,
        vertical_bar,
        semi_colon,
        colon,
        period,
        number,
        string,
        builtin,
        identifier,
        hash_identifier,
        comment,
        doc_comment,
        invalid,
        none,
    },
    curr_start: usize,
    tokens: TokenList,
};

/// TODO: Expand allowed codepoints to full Unicode range (for the time being it's ASCII only).
pub fn tokenize(source: []const u8, allocator: mem.Allocator) ![]const Token {
    var state = State{
        .source = source,
        .curr = .none,
        .curr_start = 0,
        .tokens = TokenList.initCapacity(allocator, source.len),
    };

    for (source) |char, i| {
        switch (state.curr) {
            .hash => nextHash(&state, char, i),
            .ampersand => nextAmpersand(&state, char, i),
            .none => nextNone(&state, char, i),
        }
    }

    return state.tokens.toOwnedSlice();
}

inline fn nextHash(state: *State, char: u8, i: usize) void {
    switch (char) {
        '?' => {
            try appendCurrIncl(state, .hash_question_mark, i);
            state.curr = .none;
        },
        'A'...'Z', 'a'...'z' => {
            state.curr = .hash_identifier;
        },
        _ => {
            try appendCurrExcl(state, .invalid, i);
            state.curr = .none;
            nextNone(state, char, i);
        },
    }
}

inline fn nextAmpersand(state: *State, char: u8, i: usize) void {
    switch (char) {
        '{' => {
            try appendCurrIncl(state, .ampersand_left_curly, i);
            state = .none;
        },
        _ => {
            try appendCurrExcl(state, .ampersand, i);
            state = .none;
            nextNone(state, char, i);
        },
    }
}

inline fn nextMinus(state: *State, char: u8, i: usize) void {
    switch (char) {
        '-' => {
            try appendCurrIncl(state, .minus_minus, i);
            state.curr = .none;
        },
        _ => {
            try appendCurrExcl(state, .minus, i);
            state = .none;
            nextNone(state, char, i);
        },
    }
}

inline fn nextUnderscore(state: *State, char: u8, i: usize) void {
    switch (char) {
        'A'...'Z', 'a'...'z' => {
            state.curr = .identifier;
        },
        _ => {
            try appendCurrExcl(state, .underscore, i);
            state = .none;
            nextNone(state, char, i);
        },
    }
}

inline fn nextEqual(state: *State, char: u8, i: usize) void {
    switch (char) {
        '>' => {
            try appendCurrIncl(state, .equal_greater_than, i);
            state = .none;
        },
        _ => {
            try appendCurrExcl(state, .equal, i);
            state = .none;
            nextNone(state, char, i);
        },
    }
}

inline fn nextVerticalBar(state: *State, char: u8, i: usize) void {
    switch (char) {
        '{' => {
            try appendCurrIncl(state, .vertical_bar_left_curly, i);
            state = .none;
        },
        _ => {
            try appendCurrExcl(state, .vertical_bar, i);
            state = .none;
            nextNone(state, char, i);
        },
    }
}

inline fn nextSemiColon(state: *State, char: u8, i: usize) void {
    switch (char) {
        '{' => {
            try appendCurrIncl(state, .semi_colon_left_curly, i);
            state = .none;
        },
    }
}

fn nextNone(state: *State, char: u8, i: usize) void {
    switch (char) {
        '`' => try appendAt(&state, .tick, i),
        '~' => try appendAt(&state, .tilde, i),
        '!' => try appendAt(&state, .exclamation, i),
        '@' => {
            state.curr = .builtin;
            state.curr_start = i;
        },
        '#' => {
            state.curr = .hash;
            state.curr_start = i;
        },
        '$' => try appendAt(&state, .dollar, i),
        '%' => try appendAt(&state, .percent, i),
        '^' => try appendAt(&state, .caret, i),
        '&' => {
            state.curr = .ampersand;
            state.curr_start = i;
        },
        '*' => try appendAt(&state, .asterisk, i),
        '(' => try appendAt(&state, .left_paren, i),
        ')' => try appendAt(&state, .right_paren, i),
        '-' => {
            state.curr = .minus;
            state.curr_start = i;
        },
        '_' => {
            state.curr = .underscore;
            state.curr_start = 1;
        },
        '=' => {
            state.curr = .equal;
            state.curr_start = i;
        },
        '+' => try appendAt(&state, .plus, i),
        '[' => try appendAt(&state, .left_square, i),
        ']' => try appendAt(&state, .right_square, i),
        '{' => try appendAt(&state, .left_curly, i),
        '}' => try appendAt(&state, .right_curly, i),
        '\\' => try appendAt(&state, .back_slash, i),
        '|' => {
            state.curr = .vertical_bar;
            state.curr_start = i;
        },
        ';' => {
            state.curr = .semi_colon;
            state.curr_start = i;
        },
        ':' => {
            state.curr = .colon;
            state.curr_start = i;
        },
        '\'' => {
            state.curr = .comment;
            state.curr_start = i;
        },
        '"' => {
            state.curr = .string;
            state.curr_start = i;
        },
        ',' => try appendAt(&state, .comma, i),
        '.' => {
            state.curr = .period;
            state.curr_start = i;
        },
        '<' => try appendAt(&state, .less_than, i),
        '>' => try appendAt(&state, .greater_than, i),
        '/' => try appendAt(&state, .forward_slash, i),
        '?' => try appendAt(&state, .question_mark, i),
        '0'...'9' => {
            state.curr = .number;
            state.curr_start = i;
        },
        'A'...'Z', 'a'...'z' => {
            state.curr = .identifier;
            state.curr_start = i;
        },
        '\n', '\t', '\r' => {
            // ignore these characters
        },
        _ => {
            // everything else is invalid
            state.curr = .invalid;
            state.curr_start = i;
        },
    }
}

inline fn appendAt(state: *State, kind: Token.Kind, at: usize) !void {
    try appendToken(state, kind, at, 1);
}

inline fn appendCurrIncl(state: *State, kind: Token.Kind, end: usize) !void {
    try appendToken(state, kind, state.curr_start, end + 1);
}

inline fn appendCurrExcl(state: *State, kind: Token.Kind, end: usize) !void {
    try appendToken(state, kind, state.curr_start, end);
}

inline fn appendToken(state: *State, kind: Token.Kind, start: usize, end: usize) !void {
    if (end <= start) {
        @panic("appendToken received an `end` value that was not greater than `start`");
    }
    try state.tokens.append(Token{
        .kind = kind,
        .start = start,
        .len = end - start,
        .raw = state.source[start..end],
    });
}
