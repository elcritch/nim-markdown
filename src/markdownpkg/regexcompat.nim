## Internal regular-expression compatibility layer.
##
## The default build uses Nim's `std/re` API. Enabling the package's `regex`
## feature switches to nim-regex, which avoids the system PCRE1 dependency.

when defined(feature.markdown.regex) or
    defined(`feature.nim-markdown.regex`):
  import std/strutils
  import pkg/regex as nimRegex

  type
    RegexFlag* = enum
      reIgnoreCase
      reMultiLine
      reDotAll
      reExtended
      reStudy

    Regex* = ref object
      value: nimRegex.Regex2

    RegexError* = nimRegex.RegexError

  proc toNimRegexFlags(flags: set[RegexFlag]): nimRegex.RegexFlags =
    ## Markdown's parser indexes strings by byte, so use byte-oriented
    ## matching to keep its offsets compatible with `std/re`.
    result.incl nimRegex.regexArbitraryBytes
    if reIgnoreCase in flags:
      result.incl nimRegex.regexCaseless
    if reMultiLine in flags:
      result.incl nimRegex.regexMultiline
    if reDotAll in flags:
      result.incl nimRegex.regexDotAll
    if reExtended in flags:
      result.incl nimRegex.regexExtended

  proc normalizeNamedGroups(pattern: string): string =
    ## nim-regex uses `(?P<name>...)`; PCRE also accepts `(?<name>...)`.
    result = newStringOfCap(pattern.len)
    var index = 0
    while index < pattern.len:
      if index + 3 < pattern.len and pattern[index .. index + 2] == "(?<" and
          pattern[index + 3] notin {'=', '!'}:
        result.add "(?P<"
        index += 3
      else:
        result.add pattern[index]
        inc index

  proc re*(pattern: string, flags: set[RegexFlag] = {reStudy}): Regex =
    let regexFlags = flags.toNimRegexFlags()
    Regex(value: nimRegex.re2(pattern.normalizeNamedGroups(), regexFlags))

  proc normalizedLimit(text: string, limit: int): int {.inline.} =
    if limit <= 0:
      text.len
    else:
      min(limit, text.len)

  proc isWithin(bounds: Slice[int], limit: int): bool {.inline.} =
    bounds.a <= limit and bounds.b < limit

  proc findMatch(
      text: string, pattern: Regex, start, limit: int, matched: var nimRegex.RegexMatch2
  ): bool =
    if pattern.isNil or start < 0 or start > limit:
      return
    let searchText =
      if limit < text.len:
        text[0 ..< limit]
      else:
        text
    if not nimRegex.find(searchText, pattern.value, matched, start):
      return
    result = matched.boundaries.isWithin(limit)

  proc copyCaptures(
      text: string, matched: nimRegex.RegexMatch2, captures: var openArray[string]
  ) =
    for index in 0 ..< captures.len:
      if index < matched.captures.len:
        let bounds = matched.captures[index]
        captures[index] =
          if bounds.a <= bounds.b:
            text[bounds]
          else:
            ""

  proc matchLen*(
      text: string,
      pattern: Regex,
      captures: var openArray[string],
      start = 0,
      bufSize = 0,
  ): int =
    let limit = text.normalizedLimit(bufSize)
    var matched: nimRegex.RegexMatch2
    if text.findMatch(pattern, start, limit, matched) and matched.boundaries.a == start:
      text.copyCaptures(matched, captures)
      return matched.boundaries.b - matched.boundaries.a + 1
    -1

  proc matchLen*(text: string, pattern: Regex, start = 0, bufSize = 0): int =
    var captures: array[0, string]
    text.matchLen(pattern, captures, start, bufSize)

  proc match*(text: string, pattern: Regex, start = 0): bool =
    text.matchLen(pattern, start) != -1

  proc match*(
      text: string, pattern: Regex, captures: var openArray[string], start = 0
  ): bool =
    text.matchLen(pattern, captures, start) != -1

  proc find*(text: string, pattern: Regex, start = 0, bufSize = 0): int =
    let limit = text.normalizedLimit(bufSize)
    var matched: nimRegex.RegexMatch2
    if text.findMatch(pattern, start, limit, matched):
      return matched.boundaries.a
    -1

  proc contains*(text: string, pattern: Regex, start = 0): bool =
    text.find(pattern, start) != -1

  proc findAll*(text: string, pattern: Regex, start = 0): seq[string] =
    if pattern.isNil:
      return
    for matched in nimRegex.findAll(text, pattern.value, start):
      let bounds = matched.boundaries
      result.add(
        if bounds.a <= bounds.b:
          text[bounds]
        else:
          ""
      )

  proc replace*(text: string, sub: Regex, by = ""): string =
    if sub.isNil:
      return text
    var previous = 0
    for matched in nimRegex.findAll(text, sub.value):
      let bounds = matched.boundaries
      result.add text[previous ..< bounds.a]
      result.add by
      previous = bounds.b + 1
    result.add text[previous ..< text.len]

  proc replacef*(text: string, sub: Regex, by: string): string =
    if sub.isNil:
      return text
    var previous = 0
    for matched in nimRegex.findAll(text, sub.value):
      let bounds = matched.boundaries
      result.add text[previous ..< bounds.a]
      var captures = newSeq[string](matched.captures.len)
      text.copyCaptures(matched, captures)
      result.addf(by, captures)
      previous = bounds.b + 1
    result.add text[previous ..< text.len]

else:
  import std/re as pcreRe

  export pcreRe
