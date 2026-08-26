import std/unittest
import ../src/modules/lmatch  # adjust to wherever MatchState/doMatch etc. actually live
import ../src/lerror

suite "doMatch: plain literals":
  test "a literal matches and returns the end position":
    var ms = MatchState(pattern: "abc", subject: "abc")
    check doMatch(ms, 0, 0) == 3

  test "a literal matches a PREFIX of a longer subject":
    var ms = MatchState(pattern: "abc", subject: "abcdef")
    check doMatch(ms, 0, 0) == 3

  test "a mismatched literal fails":
    var ms = MatchState(pattern: "abc", subject: "abx")
    check doMatch(ms, 0, 0) == -1

suite "doMatch: '.' and character classes":
  test "'.' matches any single character":
    var ms = MatchState(pattern: "a.c", subject: "axc")
    check doMatch(ms, 0, 0) == 3

  test "'.' still requires SOME character -- doesn't match past the end":
    var ms = MatchState(pattern: "a.c", subject: "ac")
    check doMatch(ms, 0, 0) == -1

  test "%d matches digits and rejects non-digits":
    var ms1 = MatchState(pattern: "%d%d", subject: "42")
    check doMatch(ms1, 0, 0) == 2
    var ms2 = MatchState(pattern: "%d%d", subject: "4x")
    check doMatch(ms2, 0, 0) == -1

suite "doMatch: quantifiers":
  test "'*' greedily matches as many as possible, including zero":
    var ms1 = MatchState(pattern: "a*", subject: "aaa")
    check doMatch(ms1, 0, 0) == 3
    var ms2 = MatchState(pattern: "a*", subject: "bbb")
    check doMatch(ms2, 0, 0) == 0

  test "'+' requires at least one":
    var ms1 = MatchState(pattern: "a+", subject: "aaa")
    check doMatch(ms1, 0, 0) == 3
    var ms2 = MatchState(pattern: "a+", subject: "bbb")
    check doMatch(ms2, 0, 0) == -1

  test "'?' matches zero or one":
    var ms1 = MatchState(pattern: "a?b", subject: "ab")
    check doMatch(ms1, 0, 0) == 2
    var ms2 = MatchState(pattern: "a?b", subject: "b")
    check doMatch(ms2, 0, 0) == 1

  test "'*' correctly BACKS OFF when the greedy maximum leaves nothing for what follows":
    var ms = MatchState(pattern: "a*a", subject: "aaa")
    check doMatch(ms, 0, 0) == 3

  test "'-' (lazy) stops at the FIRST opportunity, unlike greedy '*'":
    var ms = MatchState(pattern: ".-e", subject: "aeae")
    check doMatch(ms, 0, 0) == 2

  test "'*' (greedy) consumes all the way to the LAST opportunity":
    var ms = MatchState(pattern: ".*e", subject: "aeae")
    check doMatch(ms, 0, 0) == 4

suite "doMatch: anchors":
  test "'$' succeeds only when the match reaches the true end of the subject":
    var ms = MatchState(pattern: "c$", subject: "abc")
    check doMatch(ms, 2, 0) == 3

  test "'$' fails if starting position doesn't lead to the string's actual end":
    var ms = MatchState(pattern: "c$", subject: "abc")
    check doMatch(ms, 0, 0) == -1

suite "doMatch: captures":
  test "plain captures record the right start/length":
    var ms = MatchState(pattern: "(a)(b)", subject: "ab")
    check doMatch(ms, 0, 0) == 2
    check ms.captures.len == 2
    check ms.captures[0] == CaptureInfo(start: 0, len: 1)
    check ms.captures[1] == CaptureInfo(start: 1, len: 1)

  test "() captures the current byte position, not a substring":
    var ms = MatchState(pattern: "a()", subject: "ab")
    check doMatch(ms, 0, 0) == 1
    check ms.captures.len == 1
    check ms.captures[0].start == 1
    check ms.captures[0].len == CapPosition

  test "a failed match undoes any capture it speculatively started":
    var ms = MatchState(pattern: "(a)b", subject: "ac")
    check doMatch(ms, 0, 0) == -1
    check ms.captures.len == 0