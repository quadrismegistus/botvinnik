"use strict";
var maiaBrain = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // flutter/native_src/maia-brain.ts
  var maia_brain_exports = {};
  __export(maia_brain_exports, {
    MAIA_BRAIN_VERSION: () => MAIA_BRAIN_VERSION,
    maiaPick: () => maiaPick,
    maiaPlanes: () => maiaPlanes
  });

  // node_modules/chess.js/dist/esm/chess.js
  function rootNode(comment) {
    return comment !== null ? { comment, variations: [] } : { variations: [] };
  }
  function node(move, suffix, nag, comment, variations) {
    const node2 = { move, variations };
    if (suffix) {
      node2.suffix = suffix;
    }
    if (nag) {
      node2.nag = nag;
    }
    if (comment !== null) {
      node2.comment = comment;
    }
    return node2;
  }
  function lineToTree(...nodes) {
    const [root, ...rest] = nodes;
    let parent = root;
    for (const child of rest) {
      if (child !== null) {
        parent.variations = [child, ...child.variations];
        child.variations = [];
        parent = child;
      }
    }
    return root;
  }
  function pgn(headers, game) {
    if (game.marker && game.marker.comment) {
      let node2 = game.root;
      while (true) {
        const next = node2.variations[0];
        if (!next) {
          node2.comment = game.marker.comment;
          break;
        }
        node2 = next;
      }
    }
    return {
      headers,
      root: game.root,
      result: (game.marker && game.marker.result) ?? void 0
    };
  }
  function peg$subclass(child, parent) {
    function C() {
      this.constructor = child;
    }
    C.prototype = parent.prototype;
    child.prototype = new C();
  }
  function peg$SyntaxError(message, expected, found, location) {
    var self = Error.call(this, message);
    if (Object.setPrototypeOf) {
      Object.setPrototypeOf(self, peg$SyntaxError.prototype);
    }
    self.expected = expected;
    self.found = found;
    self.location = location;
    self.name = "SyntaxError";
    return self;
  }
  peg$subclass(peg$SyntaxError, Error);
  function peg$padEnd(str, targetLength, padString) {
    padString = padString || " ";
    if (str.length > targetLength) {
      return str;
    }
    targetLength -= str.length;
    padString += padString.repeat(targetLength);
    return str + padString.slice(0, targetLength);
  }
  peg$SyntaxError.prototype.format = function(sources) {
    var str = "Error: " + this.message;
    if (this.location) {
      var src = null;
      var k;
      for (k = 0; k < sources.length; k++) {
        if (sources[k].source === this.location.source) {
          src = sources[k].text.split(/\r\n|\n|\r/g);
          break;
        }
      }
      var s = this.location.start;
      var offset_s = this.location.source && typeof this.location.source.offset === "function" ? this.location.source.offset(s) : s;
      var loc = this.location.source + ":" + offset_s.line + ":" + offset_s.column;
      if (src) {
        var e = this.location.end;
        var filler = peg$padEnd("", offset_s.line.toString().length, " ");
        var line = src[s.line - 1];
        var last = s.line === e.line ? e.column : line.length + 1;
        var hatLen = last - s.column || 1;
        str += "\n --> " + loc + "\n" + filler + " |\n" + offset_s.line + " | " + line + "\n" + filler + " | " + peg$padEnd("", s.column - 1, " ") + peg$padEnd("", hatLen, "^");
      } else {
        str += "\n at " + loc;
      }
    }
    return str;
  };
  peg$SyntaxError.buildMessage = function(expected, found) {
    var DESCRIBE_EXPECTATION_FNS = {
      literal: function(expectation) {
        return '"' + literalEscape(expectation.text) + '"';
      },
      class: function(expectation) {
        var escapedParts = expectation.parts.map(function(part) {
          return Array.isArray(part) ? classEscape(part[0]) + "-" + classEscape(part[1]) : classEscape(part);
        });
        return "[" + (expectation.inverted ? "^" : "") + escapedParts.join("") + "]";
      },
      any: function() {
        return "any character";
      },
      end: function() {
        return "end of input";
      },
      other: function(expectation) {
        return expectation.description;
      }
    };
    function hex(ch) {
      return ch.charCodeAt(0).toString(16).toUpperCase();
    }
    function literalEscape(s) {
      return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\0/g, "\\0").replace(/\t/g, "\\t").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/[\x00-\x0F]/g, function(ch) {
        return "\\x0" + hex(ch);
      }).replace(/[\x10-\x1F\x7F-\x9F]/g, function(ch) {
        return "\\x" + hex(ch);
      });
    }
    function classEscape(s) {
      return s.replace(/\\/g, "\\\\").replace(/\]/g, "\\]").replace(/\^/g, "\\^").replace(/-/g, "\\-").replace(/\0/g, "\\0").replace(/\t/g, "\\t").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/[\x00-\x0F]/g, function(ch) {
        return "\\x0" + hex(ch);
      }).replace(/[\x10-\x1F\x7F-\x9F]/g, function(ch) {
        return "\\x" + hex(ch);
      });
    }
    function describeExpectation(expectation) {
      return DESCRIBE_EXPECTATION_FNS[expectation.type](expectation);
    }
    function describeExpected(expected2) {
      var descriptions = expected2.map(describeExpectation);
      var i, j;
      descriptions.sort();
      if (descriptions.length > 0) {
        for (i = 1, j = 1; i < descriptions.length; i++) {
          if (descriptions[i - 1] !== descriptions[i]) {
            descriptions[j] = descriptions[i];
            j++;
          }
        }
        descriptions.length = j;
      }
      switch (descriptions.length) {
        case 1:
          return descriptions[0];
        case 2:
          return descriptions[0] + " or " + descriptions[1];
        default:
          return descriptions.slice(0, -1).join(", ") + ", or " + descriptions[descriptions.length - 1];
      }
    }
    function describeFound(found2) {
      return found2 ? '"' + literalEscape(found2) + '"' : "end of input";
    }
    return "Expected " + describeExpected(expected) + " but " + describeFound(found) + " found.";
  };
  function peg$parse(input, options) {
    options = options !== void 0 ? options : {};
    var peg$FAILED = {};
    var peg$source = options.grammarSource;
    var peg$startRuleFunctions = { pgn: peg$parsepgn };
    var peg$startRuleFunction = peg$parsepgn;
    var peg$c0 = "[";
    var peg$c1 = '"';
    var peg$c2 = "]";
    var peg$c3 = ".";
    var peg$c4 = "O-O-O";
    var peg$c5 = "O-O";
    var peg$c6 = "0-0-0";
    var peg$c7 = "0-0";
    var peg$c8 = "$";
    var peg$c9 = "{";
    var peg$c10 = "}";
    var peg$c11 = ";";
    var peg$c12 = "(";
    var peg$c13 = ")";
    var peg$c14 = "1-0";
    var peg$c15 = "0-1";
    var peg$c16 = "1/2-1/2";
    var peg$c17 = "*";
    var peg$r0 = /^[a-zA-Z]/;
    var peg$r1 = /^[^"]/;
    var peg$r2 = /^[0-9]/;
    var peg$r3 = /^[.]/;
    var peg$r4 = /^[a-zA-Z1-8\-=]/;
    var peg$r5 = /^[+#]/;
    var peg$r6 = /^[!?]/;
    var peg$r7 = /^[^}]/;
    var peg$r8 = /^[^\r\n]/;
    var peg$r9 = /^[ \t\r\n]/;
    var peg$e0 = peg$otherExpectation("tag pair");
    var peg$e1 = peg$literalExpectation("[", false);
    var peg$e2 = peg$literalExpectation('"', false);
    var peg$e3 = peg$literalExpectation("]", false);
    var peg$e4 = peg$otherExpectation("tag name");
    var peg$e5 = peg$classExpectation([["a", "z"], ["A", "Z"]], false, false);
    var peg$e6 = peg$otherExpectation("tag value");
    var peg$e7 = peg$classExpectation(['"'], true, false);
    var peg$e8 = peg$otherExpectation("move number");
    var peg$e9 = peg$classExpectation([["0", "9"]], false, false);
    var peg$e10 = peg$literalExpectation(".", false);
    var peg$e11 = peg$classExpectation(["."], false, false);
    var peg$e12 = peg$otherExpectation("standard algebraic notation");
    var peg$e13 = peg$literalExpectation("O-O-O", false);
    var peg$e14 = peg$literalExpectation("O-O", false);
    var peg$e15 = peg$literalExpectation("0-0-0", false);
    var peg$e16 = peg$literalExpectation("0-0", false);
    var peg$e17 = peg$classExpectation([["a", "z"], ["A", "Z"], ["1", "8"], "-", "="], false, false);
    var peg$e18 = peg$classExpectation(["+", "#"], false, false);
    var peg$e19 = peg$otherExpectation("suffix annotation");
    var peg$e20 = peg$classExpectation(["!", "?"], false, false);
    var peg$e21 = peg$otherExpectation("NAG");
    var peg$e22 = peg$literalExpectation("$", false);
    var peg$e23 = peg$otherExpectation("brace comment");
    var peg$e24 = peg$literalExpectation("{", false);
    var peg$e25 = peg$classExpectation(["}"], true, false);
    var peg$e26 = peg$literalExpectation("}", false);
    var peg$e27 = peg$otherExpectation("rest of line comment");
    var peg$e28 = peg$literalExpectation(";", false);
    var peg$e29 = peg$classExpectation(["\r", "\n"], true, false);
    var peg$e30 = peg$otherExpectation("variation");
    var peg$e31 = peg$literalExpectation("(", false);
    var peg$e32 = peg$literalExpectation(")", false);
    var peg$e33 = peg$otherExpectation("game termination marker");
    var peg$e34 = peg$literalExpectation("1-0", false);
    var peg$e35 = peg$literalExpectation("0-1", false);
    var peg$e36 = peg$literalExpectation("1/2-1/2", false);
    var peg$e37 = peg$literalExpectation("*", false);
    var peg$e38 = peg$otherExpectation("whitespace");
    var peg$e39 = peg$classExpectation([" ", "	", "\r", "\n"], false, false);
    var peg$f0 = function(headers, game) {
      return pgn(headers, game);
    };
    var peg$f1 = function(tagPairs) {
      return Object.fromEntries(tagPairs);
    };
    var peg$f2 = function(tagName, tagValue) {
      return [tagName, tagValue];
    };
    var peg$f3 = function(root, marker) {
      return { root, marker };
    };
    var peg$f4 = function(comment, moves) {
      return lineToTree(rootNode(comment), ...moves.flat());
    };
    var peg$f5 = function(san, suffix, nag, comment, variations) {
      return node(san, suffix, nag, comment, variations);
    };
    var peg$f6 = function(nag) {
      return nag;
    };
    var peg$f7 = function(comment) {
      return comment.replace(/[\r\n]+/g, " ");
    };
    var peg$f8 = function(comment) {
      return comment.trim();
    };
    var peg$f9 = function(line) {
      return line;
    };
    var peg$f10 = function(result, comment) {
      return { result, comment };
    };
    var peg$currPos = options.peg$currPos | 0;
    var peg$posDetailsCache = [{ line: 1, column: 1 }];
    var peg$maxFailPos = peg$currPos;
    var peg$maxFailExpected = options.peg$maxFailExpected || [];
    var peg$silentFails = options.peg$silentFails | 0;
    var peg$result;
    if (options.startRule) {
      if (!(options.startRule in peg$startRuleFunctions)) {
        throw new Error(`Can't start parsing from rule "` + options.startRule + '".');
      }
      peg$startRuleFunction = peg$startRuleFunctions[options.startRule];
    }
    function peg$literalExpectation(text, ignoreCase) {
      return { type: "literal", text, ignoreCase };
    }
    function peg$classExpectation(parts, inverted, ignoreCase) {
      return { type: "class", parts, inverted, ignoreCase };
    }
    function peg$endExpectation() {
      return { type: "end" };
    }
    function peg$otherExpectation(description) {
      return { type: "other", description };
    }
    function peg$computePosDetails(pos) {
      var details = peg$posDetailsCache[pos];
      var p;
      if (details) {
        return details;
      } else {
        if (pos >= peg$posDetailsCache.length) {
          p = peg$posDetailsCache.length - 1;
        } else {
          p = pos;
          while (!peg$posDetailsCache[--p]) {
          }
        }
        details = peg$posDetailsCache[p];
        details = {
          line: details.line,
          column: details.column
        };
        while (p < pos) {
          if (input.charCodeAt(p) === 10) {
            details.line++;
            details.column = 1;
          } else {
            details.column++;
          }
          p++;
        }
        peg$posDetailsCache[pos] = details;
        return details;
      }
    }
    function peg$computeLocation(startPos, endPos, offset) {
      var startPosDetails = peg$computePosDetails(startPos);
      var endPosDetails = peg$computePosDetails(endPos);
      var res = {
        source: peg$source,
        start: {
          offset: startPos,
          line: startPosDetails.line,
          column: startPosDetails.column
        },
        end: {
          offset: endPos,
          line: endPosDetails.line,
          column: endPosDetails.column
        }
      };
      return res;
    }
    function peg$fail(expected) {
      if (peg$currPos < peg$maxFailPos) {
        return;
      }
      if (peg$currPos > peg$maxFailPos) {
        peg$maxFailPos = peg$currPos;
        peg$maxFailExpected = [];
      }
      peg$maxFailExpected.push(expected);
    }
    function peg$buildStructuredError(expected, found, location) {
      return new peg$SyntaxError(
        peg$SyntaxError.buildMessage(expected, found),
        expected,
        found,
        location
      );
    }
    function peg$parsepgn() {
      var s0, s1, s2;
      s0 = peg$currPos;
      s1 = peg$parsetagPairSection();
      s2 = peg$parsemoveTextSection();
      s0 = peg$f0(s1, s2);
      return s0;
    }
    function peg$parsetagPairSection() {
      var s0, s1, s2;
      s0 = peg$currPos;
      s1 = [];
      s2 = peg$parsetagPair();
      while (s2 !== peg$FAILED) {
        s1.push(s2);
        s2 = peg$parsetagPair();
      }
      s2 = peg$parse_();
      s0 = peg$f1(s1);
      return s0;
    }
    function peg$parsetagPair() {
      var s0, s2, s4, s6, s7, s8, s10;
      peg$silentFails++;
      s0 = peg$currPos;
      peg$parse_();
      if (input.charCodeAt(peg$currPos) === 91) {
        s2 = peg$c0;
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e1);
        }
      }
      if (s2 !== peg$FAILED) {
        peg$parse_();
        s4 = peg$parsetagName();
        if (s4 !== peg$FAILED) {
          peg$parse_();
          if (input.charCodeAt(peg$currPos) === 34) {
            s6 = peg$c1;
            peg$currPos++;
          } else {
            s6 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e2);
            }
          }
          if (s6 !== peg$FAILED) {
            s7 = peg$parsetagValue();
            if (input.charCodeAt(peg$currPos) === 34) {
              s8 = peg$c1;
              peg$currPos++;
            } else {
              s8 = peg$FAILED;
              if (peg$silentFails === 0) {
                peg$fail(peg$e2);
              }
            }
            if (s8 !== peg$FAILED) {
              peg$parse_();
              if (input.charCodeAt(peg$currPos) === 93) {
                s10 = peg$c2;
                peg$currPos++;
              } else {
                s10 = peg$FAILED;
                if (peg$silentFails === 0) {
                  peg$fail(peg$e3);
                }
              }
              if (s10 !== peg$FAILED) {
                s0 = peg$f2(s4, s7);
              } else {
                peg$currPos = s0;
                s0 = peg$FAILED;
              }
            } else {
              peg$currPos = s0;
              s0 = peg$FAILED;
            }
          } else {
            peg$currPos = s0;
            s0 = peg$FAILED;
          }
        } else {
          peg$currPos = s0;
          s0 = peg$FAILED;
        }
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        if (peg$silentFails === 0) {
          peg$fail(peg$e0);
        }
      }
      return s0;
    }
    function peg$parsetagName() {
      var s0, s1, s2;
      peg$silentFails++;
      s0 = peg$currPos;
      s1 = [];
      s2 = input.charAt(peg$currPos);
      if (peg$r0.test(s2)) {
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e5);
        }
      }
      if (s2 !== peg$FAILED) {
        while (s2 !== peg$FAILED) {
          s1.push(s2);
          s2 = input.charAt(peg$currPos);
          if (peg$r0.test(s2)) {
            peg$currPos++;
          } else {
            s2 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e5);
            }
          }
        }
      } else {
        s1 = peg$FAILED;
      }
      if (s1 !== peg$FAILED) {
        s0 = input.substring(s0, peg$currPos);
      } else {
        s0 = s1;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e4);
        }
      }
      return s0;
    }
    function peg$parsetagValue() {
      var s0, s1, s2;
      peg$silentFails++;
      s0 = peg$currPos;
      s1 = [];
      s2 = input.charAt(peg$currPos);
      if (peg$r1.test(s2)) {
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e7);
        }
      }
      while (s2 !== peg$FAILED) {
        s1.push(s2);
        s2 = input.charAt(peg$currPos);
        if (peg$r1.test(s2)) {
          peg$currPos++;
        } else {
          s2 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e7);
          }
        }
      }
      s0 = input.substring(s0, peg$currPos);
      peg$silentFails--;
      s1 = peg$FAILED;
      if (peg$silentFails === 0) {
        peg$fail(peg$e6);
      }
      return s0;
    }
    function peg$parsemoveTextSection() {
      var s0, s1, s3;
      s0 = peg$currPos;
      s1 = peg$parseline();
      peg$parse_();
      s3 = peg$parsegameTerminationMarker();
      if (s3 === peg$FAILED) {
        s3 = null;
      }
      peg$parse_();
      s0 = peg$f3(s1, s3);
      return s0;
    }
    function peg$parseline() {
      var s0, s1, s2, s3;
      s0 = peg$currPos;
      s1 = peg$parsecomment();
      if (s1 === peg$FAILED) {
        s1 = null;
      }
      s2 = [];
      s3 = peg$parsemove();
      while (s3 !== peg$FAILED) {
        s2.push(s3);
        s3 = peg$parsemove();
      }
      s0 = peg$f4(s1, s2);
      return s0;
    }
    function peg$parsemove() {
      var s0, s4, s5, s6, s7, s8, s9, s10;
      s0 = peg$currPos;
      peg$parse_();
      peg$parsemoveNumber();
      peg$parse_();
      s4 = peg$parsesan();
      if (s4 !== peg$FAILED) {
        s5 = peg$parsesuffixAnnotation();
        if (s5 === peg$FAILED) {
          s5 = null;
        }
        s6 = [];
        s7 = peg$parsenag();
        while (s7 !== peg$FAILED) {
          s6.push(s7);
          s7 = peg$parsenag();
        }
        s7 = peg$parse_();
        s8 = peg$parsecomment();
        if (s8 === peg$FAILED) {
          s8 = null;
        }
        s9 = [];
        s10 = peg$parsevariation();
        while (s10 !== peg$FAILED) {
          s9.push(s10);
          s10 = peg$parsevariation();
        }
        s0 = peg$f5(s4, s5, s6, s8, s9);
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      return s0;
    }
    function peg$parsemoveNumber() {
      var s0, s1, s2, s3, s4, s5;
      peg$silentFails++;
      s0 = peg$currPos;
      s1 = [];
      s2 = input.charAt(peg$currPos);
      if (peg$r2.test(s2)) {
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e9);
        }
      }
      while (s2 !== peg$FAILED) {
        s1.push(s2);
        s2 = input.charAt(peg$currPos);
        if (peg$r2.test(s2)) {
          peg$currPos++;
        } else {
          s2 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e9);
          }
        }
      }
      if (input.charCodeAt(peg$currPos) === 46) {
        s2 = peg$c3;
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e10);
        }
      }
      if (s2 !== peg$FAILED) {
        s3 = peg$parse_();
        s4 = [];
        s5 = input.charAt(peg$currPos);
        if (peg$r3.test(s5)) {
          peg$currPos++;
        } else {
          s5 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e11);
          }
        }
        while (s5 !== peg$FAILED) {
          s4.push(s5);
          s5 = input.charAt(peg$currPos);
          if (peg$r3.test(s5)) {
            peg$currPos++;
          } else {
            s5 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e11);
            }
          }
        }
        s1 = [s1, s2, s3, s4];
        s0 = s1;
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e8);
        }
      }
      return s0;
    }
    function peg$parsesan() {
      var s0, s1, s2, s3, s4, s5;
      peg$silentFails++;
      s0 = peg$currPos;
      s1 = peg$currPos;
      if (input.substr(peg$currPos, 5) === peg$c4) {
        s2 = peg$c4;
        peg$currPos += 5;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e13);
        }
      }
      if (s2 === peg$FAILED) {
        if (input.substr(peg$currPos, 3) === peg$c5) {
          s2 = peg$c5;
          peg$currPos += 3;
        } else {
          s2 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e14);
          }
        }
        if (s2 === peg$FAILED) {
          if (input.substr(peg$currPos, 5) === peg$c6) {
            s2 = peg$c6;
            peg$currPos += 5;
          } else {
            s2 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e15);
            }
          }
          if (s2 === peg$FAILED) {
            if (input.substr(peg$currPos, 3) === peg$c7) {
              s2 = peg$c7;
              peg$currPos += 3;
            } else {
              s2 = peg$FAILED;
              if (peg$silentFails === 0) {
                peg$fail(peg$e16);
              }
            }
            if (s2 === peg$FAILED) {
              s2 = peg$currPos;
              s3 = input.charAt(peg$currPos);
              if (peg$r0.test(s3)) {
                peg$currPos++;
              } else {
                s3 = peg$FAILED;
                if (peg$silentFails === 0) {
                  peg$fail(peg$e5);
                }
              }
              if (s3 !== peg$FAILED) {
                s4 = [];
                s5 = input.charAt(peg$currPos);
                if (peg$r4.test(s5)) {
                  peg$currPos++;
                } else {
                  s5 = peg$FAILED;
                  if (peg$silentFails === 0) {
                    peg$fail(peg$e17);
                  }
                }
                if (s5 !== peg$FAILED) {
                  while (s5 !== peg$FAILED) {
                    s4.push(s5);
                    s5 = input.charAt(peg$currPos);
                    if (peg$r4.test(s5)) {
                      peg$currPos++;
                    } else {
                      s5 = peg$FAILED;
                      if (peg$silentFails === 0) {
                        peg$fail(peg$e17);
                      }
                    }
                  }
                } else {
                  s4 = peg$FAILED;
                }
                if (s4 !== peg$FAILED) {
                  s3 = [s3, s4];
                  s2 = s3;
                } else {
                  peg$currPos = s2;
                  s2 = peg$FAILED;
                }
              } else {
                peg$currPos = s2;
                s2 = peg$FAILED;
              }
            }
          }
        }
      }
      if (s2 !== peg$FAILED) {
        s3 = input.charAt(peg$currPos);
        if (peg$r5.test(s3)) {
          peg$currPos++;
        } else {
          s3 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e18);
          }
        }
        if (s3 === peg$FAILED) {
          s3 = null;
        }
        s2 = [s2, s3];
        s1 = s2;
      } else {
        peg$currPos = s1;
        s1 = peg$FAILED;
      }
      if (s1 !== peg$FAILED) {
        s0 = input.substring(s0, peg$currPos);
      } else {
        s0 = s1;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e12);
        }
      }
      return s0;
    }
    function peg$parsesuffixAnnotation() {
      var s0, s1, s2;
      peg$silentFails++;
      s0 = peg$currPos;
      s1 = [];
      s2 = input.charAt(peg$currPos);
      if (peg$r6.test(s2)) {
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e20);
        }
      }
      while (s2 !== peg$FAILED) {
        s1.push(s2);
        if (s1.length >= 2) {
          s2 = peg$FAILED;
        } else {
          s2 = input.charAt(peg$currPos);
          if (peg$r6.test(s2)) {
            peg$currPos++;
          } else {
            s2 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e20);
            }
          }
        }
      }
      if (s1.length < 1) {
        peg$currPos = s0;
        s0 = peg$FAILED;
      } else {
        s0 = s1;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e19);
        }
      }
      return s0;
    }
    function peg$parsenag() {
      var s0, s2, s3, s4, s5;
      peg$silentFails++;
      s0 = peg$currPos;
      peg$parse_();
      if (input.charCodeAt(peg$currPos) === 36) {
        s2 = peg$c8;
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e22);
        }
      }
      if (s2 !== peg$FAILED) {
        s3 = peg$currPos;
        s4 = [];
        s5 = input.charAt(peg$currPos);
        if (peg$r2.test(s5)) {
          peg$currPos++;
        } else {
          s5 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e9);
          }
        }
        if (s5 !== peg$FAILED) {
          while (s5 !== peg$FAILED) {
            s4.push(s5);
            s5 = input.charAt(peg$currPos);
            if (peg$r2.test(s5)) {
              peg$currPos++;
            } else {
              s5 = peg$FAILED;
              if (peg$silentFails === 0) {
                peg$fail(peg$e9);
              }
            }
          }
        } else {
          s4 = peg$FAILED;
        }
        if (s4 !== peg$FAILED) {
          s3 = input.substring(s3, peg$currPos);
        } else {
          s3 = s4;
        }
        if (s3 !== peg$FAILED) {
          s0 = peg$f6(s3);
        } else {
          peg$currPos = s0;
          s0 = peg$FAILED;
        }
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        if (peg$silentFails === 0) {
          peg$fail(peg$e21);
        }
      }
      return s0;
    }
    function peg$parsecomment() {
      var s0;
      s0 = peg$parsebraceComment();
      if (s0 === peg$FAILED) {
        s0 = peg$parserestOfLineComment();
      }
      return s0;
    }
    function peg$parsebraceComment() {
      var s0, s1, s2, s3, s4;
      peg$silentFails++;
      s0 = peg$currPos;
      if (input.charCodeAt(peg$currPos) === 123) {
        s1 = peg$c9;
        peg$currPos++;
      } else {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e24);
        }
      }
      if (s1 !== peg$FAILED) {
        s2 = peg$currPos;
        s3 = [];
        s4 = input.charAt(peg$currPos);
        if (peg$r7.test(s4)) {
          peg$currPos++;
        } else {
          s4 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e25);
          }
        }
        while (s4 !== peg$FAILED) {
          s3.push(s4);
          s4 = input.charAt(peg$currPos);
          if (peg$r7.test(s4)) {
            peg$currPos++;
          } else {
            s4 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e25);
            }
          }
        }
        s2 = input.substring(s2, peg$currPos);
        if (input.charCodeAt(peg$currPos) === 125) {
          s3 = peg$c10;
          peg$currPos++;
        } else {
          s3 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e26);
          }
        }
        if (s3 !== peg$FAILED) {
          s0 = peg$f7(s2);
        } else {
          peg$currPos = s0;
          s0 = peg$FAILED;
        }
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e23);
        }
      }
      return s0;
    }
    function peg$parserestOfLineComment() {
      var s0, s1, s2, s3, s4;
      peg$silentFails++;
      s0 = peg$currPos;
      if (input.charCodeAt(peg$currPos) === 59) {
        s1 = peg$c11;
        peg$currPos++;
      } else {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e28);
        }
      }
      if (s1 !== peg$FAILED) {
        s2 = peg$currPos;
        s3 = [];
        s4 = input.charAt(peg$currPos);
        if (peg$r8.test(s4)) {
          peg$currPos++;
        } else {
          s4 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e29);
          }
        }
        while (s4 !== peg$FAILED) {
          s3.push(s4);
          s4 = input.charAt(peg$currPos);
          if (peg$r8.test(s4)) {
            peg$currPos++;
          } else {
            s4 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e29);
            }
          }
        }
        s2 = input.substring(s2, peg$currPos);
        s0 = peg$f8(s2);
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e27);
        }
      }
      return s0;
    }
    function peg$parsevariation() {
      var s0, s2, s3, s5;
      peg$silentFails++;
      s0 = peg$currPos;
      peg$parse_();
      if (input.charCodeAt(peg$currPos) === 40) {
        s2 = peg$c12;
        peg$currPos++;
      } else {
        s2 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e31);
        }
      }
      if (s2 !== peg$FAILED) {
        s3 = peg$parseline();
        if (s3 !== peg$FAILED) {
          peg$parse_();
          if (input.charCodeAt(peg$currPos) === 41) {
            s5 = peg$c13;
            peg$currPos++;
          } else {
            s5 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e32);
            }
          }
          if (s5 !== peg$FAILED) {
            s0 = peg$f9(s3);
          } else {
            peg$currPos = s0;
            s0 = peg$FAILED;
          }
        } else {
          peg$currPos = s0;
          s0 = peg$FAILED;
        }
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        if (peg$silentFails === 0) {
          peg$fail(peg$e30);
        }
      }
      return s0;
    }
    function peg$parsegameTerminationMarker() {
      var s0, s1, s3;
      peg$silentFails++;
      s0 = peg$currPos;
      if (input.substr(peg$currPos, 3) === peg$c14) {
        s1 = peg$c14;
        peg$currPos += 3;
      } else {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e34);
        }
      }
      if (s1 === peg$FAILED) {
        if (input.substr(peg$currPos, 3) === peg$c15) {
          s1 = peg$c15;
          peg$currPos += 3;
        } else {
          s1 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e35);
          }
        }
        if (s1 === peg$FAILED) {
          if (input.substr(peg$currPos, 7) === peg$c16) {
            s1 = peg$c16;
            peg$currPos += 7;
          } else {
            s1 = peg$FAILED;
            if (peg$silentFails === 0) {
              peg$fail(peg$e36);
            }
          }
          if (s1 === peg$FAILED) {
            if (input.charCodeAt(peg$currPos) === 42) {
              s1 = peg$c17;
              peg$currPos++;
            } else {
              s1 = peg$FAILED;
              if (peg$silentFails === 0) {
                peg$fail(peg$e37);
              }
            }
          }
        }
      }
      if (s1 !== peg$FAILED) {
        peg$parse_();
        s3 = peg$parsecomment();
        if (s3 === peg$FAILED) {
          s3 = null;
        }
        s0 = peg$f10(s1, s3);
      } else {
        peg$currPos = s0;
        s0 = peg$FAILED;
      }
      peg$silentFails--;
      if (s0 === peg$FAILED) {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e33);
        }
      }
      return s0;
    }
    function peg$parse_() {
      var s0, s1;
      peg$silentFails++;
      s0 = [];
      s1 = input.charAt(peg$currPos);
      if (peg$r9.test(s1)) {
        peg$currPos++;
      } else {
        s1 = peg$FAILED;
        if (peg$silentFails === 0) {
          peg$fail(peg$e39);
        }
      }
      while (s1 !== peg$FAILED) {
        s0.push(s1);
        s1 = input.charAt(peg$currPos);
        if (peg$r9.test(s1)) {
          peg$currPos++;
        } else {
          s1 = peg$FAILED;
          if (peg$silentFails === 0) {
            peg$fail(peg$e39);
          }
        }
      }
      peg$silentFails--;
      s1 = peg$FAILED;
      if (peg$silentFails === 0) {
        peg$fail(peg$e38);
      }
      return s0;
    }
    peg$result = peg$startRuleFunction();
    if (options.peg$library) {
      return (
        /** @type {any} */
        {
          peg$result,
          peg$currPos,
          peg$FAILED,
          peg$maxFailExpected,
          peg$maxFailPos
        }
      );
    }
    if (peg$result !== peg$FAILED && peg$currPos === input.length) {
      return peg$result;
    } else {
      if (peg$result !== peg$FAILED && peg$currPos < input.length) {
        peg$fail(peg$endExpectation());
      }
      throw peg$buildStructuredError(
        peg$maxFailExpected,
        peg$maxFailPos < input.length ? input.charAt(peg$maxFailPos) : null,
        peg$maxFailPos < input.length ? peg$computeLocation(peg$maxFailPos, peg$maxFailPos + 1) : peg$computeLocation(peg$maxFailPos, peg$maxFailPos)
      );
    }
  }
  var MASK64 = 0xffffffffffffffffn;
  function rotl(x, k) {
    return (x << k | x >> 64n - k) & 0xffffffffffffffffn;
  }
  function wrappingMul(x, y) {
    return x * y & MASK64;
  }
  function xoroshiro128(state) {
    return function() {
      let s0 = BigInt(state & MASK64);
      let s1 = BigInt(state >> 64n & MASK64);
      const result = wrappingMul(rotl(wrappingMul(s0, 5n), 7n), 9n);
      s1 ^= s0;
      s0 = (rotl(s0, 24n) ^ s1 ^ s1 << 16n) & MASK64;
      s1 = rotl(s1, 37n);
      state = s1 << 64n | s0;
      return result;
    };
  }
  var rand = xoroshiro128(0xa187eb39cdcaed8f31c4b365b102e01en);
  var PIECE_KEYS = Array.from({ length: 2 }, () => Array.from({ length: 6 }, () => Array.from({ length: 128 }, () => rand())));
  var EP_KEYS = Array.from({ length: 8 }, () => rand());
  var CASTLING_KEYS = Array.from({ length: 16 }, () => rand());
  var SIDE_KEY = rand();
  var WHITE = "w";
  var BLACK = "b";
  var PAWN = "p";
  var KNIGHT = "n";
  var BISHOP = "b";
  var ROOK = "r";
  var QUEEN = "q";
  var KING = "k";
  var DEFAULT_POSITION = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
  var Move = class {
    color;
    from;
    to;
    piece;
    captured;
    promotion;
    /**
     * @deprecated This field is deprecated and will be removed in version 2.0.0.
     * Please use move descriptor functions instead: `isCapture`, `isPromotion`,
     * `isEnPassant`, `isKingsideCastle`, `isQueensideCastle`, `isCastle`, and
     * `isBigPawn`
     */
    flags;
    san;
    lan;
    before;
    after;
    constructor(chess, internal) {
      const { color, piece, from, to, flags, captured, promotion } = internal;
      const fromAlgebraic = algebraic(from);
      const toAlgebraic = algebraic(to);
      this.color = color;
      this.piece = piece;
      this.from = fromAlgebraic;
      this.to = toAlgebraic;
      this.san = chess["_moveToSan"](internal, chess["_moves"]({ legal: true }));
      this.lan = fromAlgebraic + toAlgebraic;
      this.before = chess.fen();
      chess["_makeMove"](internal);
      this.after = chess.fen();
      chess["_undoMove"]();
      this.flags = "";
      for (const flag in BITS) {
        if (BITS[flag] & flags) {
          this.flags += FLAGS[flag];
        }
      }
      if (captured) {
        this.captured = captured;
      }
      if (promotion) {
        this.promotion = promotion;
        this.lan += promotion;
      }
    }
    isCapture() {
      return this.flags.indexOf(FLAGS["CAPTURE"]) > -1;
    }
    isPromotion() {
      return this.flags.indexOf(FLAGS["PROMOTION"]) > -1;
    }
    isEnPassant() {
      return this.flags.indexOf(FLAGS["EP_CAPTURE"]) > -1;
    }
    isKingsideCastle() {
      return this.flags.indexOf(FLAGS["KSIDE_CASTLE"]) > -1;
    }
    isQueensideCastle() {
      return this.flags.indexOf(FLAGS["QSIDE_CASTLE"]) > -1;
    }
    isBigPawn() {
      return this.flags.indexOf(FLAGS["BIG_PAWN"]) > -1;
    }
  };
  var EMPTY = -1;
  var FLAGS = {
    NORMAL: "n",
    CAPTURE: "c",
    BIG_PAWN: "b",
    EP_CAPTURE: "e",
    PROMOTION: "p",
    KSIDE_CASTLE: "k",
    QSIDE_CASTLE: "q",
    NULL_MOVE: "-"
  };
  var BITS = {
    NORMAL: 1,
    CAPTURE: 2,
    BIG_PAWN: 4,
    EP_CAPTURE: 8,
    PROMOTION: 16,
    KSIDE_CASTLE: 32,
    QSIDE_CASTLE: 64,
    NULL_MOVE: 128
  };
  var SEVEN_TAG_ROSTER = {
    Event: "?",
    Site: "?",
    Date: "????.??.??",
    Round: "?",
    White: "?",
    Black: "?",
    Result: "*"
  };
  var SUPLEMENTAL_TAGS = {
    WhiteTitle: null,
    BlackTitle: null,
    WhiteElo: null,
    BlackElo: null,
    WhiteUSCF: null,
    BlackUSCF: null,
    WhiteNA: null,
    BlackNA: null,
    WhiteType: null,
    BlackType: null,
    EventDate: null,
    EventSponsor: null,
    Section: null,
    Stage: null,
    Board: null,
    Opening: null,
    Variation: null,
    SubVariation: null,
    ECO: null,
    NIC: null,
    Time: null,
    UTCTime: null,
    UTCDate: null,
    TimeControl: null,
    SetUp: null,
    FEN: null,
    Termination: null,
    Annotator: null,
    Mode: null,
    PlyCount: null
  };
  var HEADER_TEMPLATE = {
    ...SEVEN_TAG_ROSTER,
    ...SUPLEMENTAL_TAGS
  };
  var Ox88 = {
    a8: 0,
    b8: 1,
    c8: 2,
    d8: 3,
    e8: 4,
    f8: 5,
    g8: 6,
    h8: 7,
    a7: 16,
    b7: 17,
    c7: 18,
    d7: 19,
    e7: 20,
    f7: 21,
    g7: 22,
    h7: 23,
    a6: 32,
    b6: 33,
    c6: 34,
    d6: 35,
    e6: 36,
    f6: 37,
    g6: 38,
    h6: 39,
    a5: 48,
    b5: 49,
    c5: 50,
    d5: 51,
    e5: 52,
    f5: 53,
    g5: 54,
    h5: 55,
    a4: 64,
    b4: 65,
    c4: 66,
    d4: 67,
    e4: 68,
    f4: 69,
    g4: 70,
    h4: 71,
    a3: 80,
    b3: 81,
    c3: 82,
    d3: 83,
    e3: 84,
    f3: 85,
    g3: 86,
    h3: 87,
    a2: 96,
    b2: 97,
    c2: 98,
    d2: 99,
    e2: 100,
    f2: 101,
    g2: 102,
    h2: 103,
    a1: 112,
    b1: 113,
    c1: 114,
    d1: 115,
    e1: 116,
    f1: 117,
    g1: 118,
    h1: 119
  };
  var PAWN_OFFSETS = {
    b: [16, 32, 17, 15],
    w: [-16, -32, -17, -15]
  };
  var PIECE_OFFSETS = {
    n: [-18, -33, -31, -14, 18, 33, 31, 14],
    b: [-17, -15, 17, 15],
    r: [-16, 1, 16, -1],
    q: [-17, -16, -15, 1, 17, 16, 15, -1],
    k: [-17, -16, -15, 1, 17, 16, 15, -1]
  };
  var ATTACKS = [
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    24,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    2,
    24,
    2,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    2,
    53,
    56,
    53,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
    24,
    24,
    24,
    24,
    24,
    24,
    56,
    0,
    56,
    24,
    24,
    24,
    24,
    24,
    24,
    0,
    0,
    0,
    0,
    0,
    0,
    2,
    53,
    56,
    53,
    2,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    2,
    24,
    2,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    24,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    0,
    0,
    20,
    0,
    0,
    20,
    0,
    0,
    0,
    0,
    0,
    0,
    24,
    0,
    0,
    0,
    0,
    0,
    0,
    20
  ];
  var RAYS = [
    17,
    0,
    0,
    0,
    0,
    0,
    0,
    16,
    0,
    0,
    0,
    0,
    0,
    0,
    15,
    0,
    0,
    17,
    0,
    0,
    0,
    0,
    0,
    16,
    0,
    0,
    0,
    0,
    0,
    15,
    0,
    0,
    0,
    0,
    17,
    0,
    0,
    0,
    0,
    16,
    0,
    0,
    0,
    0,
    15,
    0,
    0,
    0,
    0,
    0,
    0,
    17,
    0,
    0,
    0,
    16,
    0,
    0,
    0,
    15,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    17,
    0,
    0,
    16,
    0,
    0,
    15,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    17,
    0,
    16,
    0,
    15,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    17,
    16,
    15,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    0,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    -1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    -15,
    -16,
    -17,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    -15,
    0,
    -16,
    0,
    -17,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    -15,
    0,
    0,
    -16,
    0,
    0,
    -17,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    -15,
    0,
    0,
    0,
    -16,
    0,
    0,
    0,
    -17,
    0,
    0,
    0,
    0,
    0,
    0,
    -15,
    0,
    0,
    0,
    0,
    -16,
    0,
    0,
    0,
    0,
    -17,
    0,
    0,
    0,
    0,
    -15,
    0,
    0,
    0,
    0,
    0,
    -16,
    0,
    0,
    0,
    0,
    0,
    -17,
    0,
    0,
    -15,
    0,
    0,
    0,
    0,
    0,
    0,
    -16,
    0,
    0,
    0,
    0,
    0,
    0,
    -17
  ];
  var PIECE_MASKS = { p: 1, n: 2, b: 4, r: 8, q: 16, k: 32 };
  var SYMBOLS = "pnbrqkPNBRQK";
  var PROMOTIONS = [KNIGHT, BISHOP, ROOK, QUEEN];
  var RANK_1 = 7;
  var RANK_2 = 6;
  var RANK_7 = 1;
  var RANK_8 = 0;
  var SIDES = {
    [KING]: BITS.KSIDE_CASTLE,
    [QUEEN]: BITS.QSIDE_CASTLE
  };
  var ROOKS = {
    w: [
      { square: Ox88.a1, flag: BITS.QSIDE_CASTLE },
      { square: Ox88.h1, flag: BITS.KSIDE_CASTLE }
    ],
    b: [
      { square: Ox88.a8, flag: BITS.QSIDE_CASTLE },
      { square: Ox88.h8, flag: BITS.KSIDE_CASTLE }
    ]
  };
  var SECOND_RANK = { b: RANK_7, w: RANK_2 };
  var SAN_NULLMOVE = "--";
  function rank(square) {
    return square >> 4;
  }
  function file(square) {
    return square & 15;
  }
  function isDigit(c) {
    return "0123456789".indexOf(c) !== -1;
  }
  function algebraic(square) {
    const f = file(square);
    const r = rank(square);
    return "abcdefgh".substring(f, f + 1) + "87654321".substring(r, r + 1);
  }
  function swapColor(color) {
    return color === WHITE ? BLACK : WHITE;
  }
  function validateFen(fen) {
    const tokens = fen.split(/\s+/);
    if (tokens.length !== 6) {
      return {
        ok: false,
        error: "Invalid FEN: must contain six space-delimited fields"
      };
    }
    const moveNumber = parseInt(tokens[5], 10);
    if (isNaN(moveNumber) || moveNumber <= 0) {
      return {
        ok: false,
        error: "Invalid FEN: move number must be a positive integer"
      };
    }
    const halfMoves = parseInt(tokens[4], 10);
    if (isNaN(halfMoves) || halfMoves < 0) {
      return {
        ok: false,
        error: "Invalid FEN: half move counter number must be a non-negative integer"
      };
    }
    if (!/^(-|[abcdefgh][36])$/.test(tokens[3])) {
      return { ok: false, error: "Invalid FEN: en-passant square is invalid" };
    }
    if (/[^kKqQ-]/.test(tokens[2])) {
      return { ok: false, error: "Invalid FEN: castling availability is invalid" };
    }
    if (!/^(w|b)$/.test(tokens[1])) {
      return { ok: false, error: "Invalid FEN: side-to-move is invalid" };
    }
    const rows = tokens[0].split("/");
    if (rows.length !== 8) {
      return {
        ok: false,
        error: "Invalid FEN: piece data does not contain 8 '/'-delimited rows"
      };
    }
    for (let i = 0; i < rows.length; i++) {
      let sumFields = 0;
      let previousWasNumber = false;
      for (let k = 0; k < rows[i].length; k++) {
        if (isDigit(rows[i][k])) {
          if (previousWasNumber) {
            return {
              ok: false,
              error: "Invalid FEN: piece data is invalid (consecutive number)"
            };
          }
          sumFields += parseInt(rows[i][k], 10);
          previousWasNumber = true;
        } else {
          if (!/^[prnbqkPRNBQK]$/.test(rows[i][k])) {
            return {
              ok: false,
              error: "Invalid FEN: piece data is invalid (invalid piece)"
            };
          }
          sumFields += 1;
          previousWasNumber = false;
        }
      }
      if (sumFields !== 8) {
        return {
          ok: false,
          error: "Invalid FEN: piece data is invalid (too many squares in rank)"
        };
      }
    }
    if (tokens[3][1] == "3" && tokens[1] == "w" || tokens[3][1] == "6" && tokens[1] == "b") {
      return { ok: false, error: "Invalid FEN: illegal en-passant square" };
    }
    const kings = [
      { color: "white", regex: /K/g },
      { color: "black", regex: /k/g }
    ];
    for (const { color, regex } of kings) {
      if (!regex.test(tokens[0])) {
        return { ok: false, error: `Invalid FEN: missing ${color} king` };
      }
      if ((tokens[0].match(regex) || []).length > 1) {
        return { ok: false, error: `Invalid FEN: too many ${color} kings` };
      }
    }
    if (Array.from(rows[0] + rows[7]).some((char) => char.toUpperCase() === "P")) {
      return {
        ok: false,
        error: "Invalid FEN: some pawns are on the edge rows"
      };
    }
    return { ok: true };
  }
  function getDisambiguator(move, moves) {
    const from = move.from;
    const to = move.to;
    const piece = move.piece;
    let ambiguities = 0;
    let sameRank = 0;
    let sameFile = 0;
    for (let i = 0, len = moves.length; i < len; i++) {
      const ambigFrom = moves[i].from;
      const ambigTo = moves[i].to;
      const ambigPiece = moves[i].piece;
      if (piece === ambigPiece && from !== ambigFrom && to === ambigTo) {
        ambiguities++;
        if (rank(from) === rank(ambigFrom)) {
          sameRank++;
        }
        if (file(from) === file(ambigFrom)) {
          sameFile++;
        }
      }
    }
    if (ambiguities > 0) {
      if (sameRank > 0 && sameFile > 0) {
        return algebraic(from);
      } else if (sameFile > 0) {
        return algebraic(from).charAt(1);
      } else {
        return algebraic(from).charAt(0);
      }
    }
    return "";
  }
  function addMove(moves, color, from, to, piece, captured = void 0, flags = BITS.NORMAL) {
    const r = rank(to);
    if (piece === PAWN && (r === RANK_1 || r === RANK_8)) {
      for (let i = 0; i < PROMOTIONS.length; i++) {
        const promotion = PROMOTIONS[i];
        moves.push({
          color,
          from,
          to,
          piece,
          captured,
          promotion,
          flags: flags | BITS.PROMOTION
        });
      }
    } else {
      moves.push({
        color,
        from,
        to,
        piece,
        captured,
        flags
      });
    }
  }
  function inferPieceType(san) {
    let pieceType = san.charAt(0);
    if (pieceType >= "a" && pieceType <= "h") {
      const matches = san.match(/[a-h]\d.*[a-h]\d/);
      if (matches) {
        return void 0;
      }
      return PAWN;
    }
    pieceType = pieceType.toLowerCase();
    if (pieceType === "o") {
      return KING;
    }
    return pieceType;
  }
  function strippedSan(move) {
    return move.replace(/=/, "").replace(/[+#]?[?!]*$/, "");
  }
  var Chess = class {
    _board = new Array(128);
    _turn = WHITE;
    _header = {};
    _kings = { w: EMPTY, b: EMPTY };
    _epSquare = -1;
    _halfMoves = 0;
    _moveNumber = 0;
    _history = [];
    _comments = {};
    _castling = { w: 0, b: 0 };
    _hash = 0n;
    // tracks number of times a position has been seen for repetition checking
    _positionCount = /* @__PURE__ */ new Map();
    constructor(fen = DEFAULT_POSITION, { skipValidation = false } = {}) {
      this.load(fen, { skipValidation });
    }
    clear({ preserveHeaders = false } = {}) {
      this._board = new Array(128);
      this._kings = { w: EMPTY, b: EMPTY };
      this._turn = WHITE;
      this._castling = { w: 0, b: 0 };
      this._epSquare = EMPTY;
      this._halfMoves = 0;
      this._moveNumber = 1;
      this._history = [];
      this._comments = {};
      this._header = preserveHeaders ? this._header : { ...HEADER_TEMPLATE };
      this._hash = this._computeHash();
      this._positionCount = /* @__PURE__ */ new Map();
      this._header["SetUp"] = null;
      this._header["FEN"] = null;
    }
    load(fen, { skipValidation = false, preserveHeaders = false } = {}) {
      let tokens = fen.split(/\s+/);
      if (tokens.length >= 2 && tokens.length < 6) {
        const adjustments = ["-", "-", "0", "1"];
        fen = tokens.concat(adjustments.slice(-(6 - tokens.length))).join(" ");
      }
      tokens = fen.split(/\s+/);
      if (!skipValidation) {
        const { ok, error } = validateFen(fen);
        if (!ok) {
          throw new Error(error);
        }
      }
      const position = tokens[0];
      let square = 0;
      this.clear({ preserveHeaders });
      for (let i = 0; i < position.length; i++) {
        const piece = position.charAt(i);
        if (piece === "/") {
          square += 8;
        } else if (isDigit(piece)) {
          square += parseInt(piece, 10);
        } else {
          const color = piece < "a" ? WHITE : BLACK;
          this._put({ type: piece.toLowerCase(), color }, algebraic(square));
          square++;
        }
      }
      this._turn = tokens[1];
      if (tokens[2].indexOf("K") > -1) {
        this._castling.w |= BITS.KSIDE_CASTLE;
      }
      if (tokens[2].indexOf("Q") > -1) {
        this._castling.w |= BITS.QSIDE_CASTLE;
      }
      if (tokens[2].indexOf("k") > -1) {
        this._castling.b |= BITS.KSIDE_CASTLE;
      }
      if (tokens[2].indexOf("q") > -1) {
        this._castling.b |= BITS.QSIDE_CASTLE;
      }
      this._epSquare = tokens[3] === "-" ? EMPTY : Ox88[tokens[3]];
      this._halfMoves = parseInt(tokens[4], 10);
      this._moveNumber = parseInt(tokens[5], 10);
      this._hash = this._computeHash();
      this._updateSetup(fen);
      this._incPositionCount();
    }
    fen({ forceEnpassantSquare = false } = {}) {
      let empty = 0;
      let fen = "";
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        if (this._board[i]) {
          if (empty > 0) {
            fen += empty;
            empty = 0;
          }
          const { color, type: piece } = this._board[i];
          fen += color === WHITE ? piece.toUpperCase() : piece.toLowerCase();
        } else {
          empty++;
        }
        if (i + 1 & 136) {
          if (empty > 0) {
            fen += empty;
          }
          if (i !== Ox88.h1) {
            fen += "/";
          }
          empty = 0;
          i += 8;
        }
      }
      let castling = "";
      if (this._castling[WHITE] & BITS.KSIDE_CASTLE) {
        castling += "K";
      }
      if (this._castling[WHITE] & BITS.QSIDE_CASTLE) {
        castling += "Q";
      }
      if (this._castling[BLACK] & BITS.KSIDE_CASTLE) {
        castling += "k";
      }
      if (this._castling[BLACK] & BITS.QSIDE_CASTLE) {
        castling += "q";
      }
      castling = castling || "-";
      let epSquare = "-";
      if (this._epSquare !== EMPTY) {
        if (forceEnpassantSquare) {
          epSquare = algebraic(this._epSquare);
        } else {
          const bigPawnSquare = this._epSquare + (this._turn === WHITE ? 16 : -16);
          const squares = [bigPawnSquare + 1, bigPawnSquare - 1];
          for (const square of squares) {
            if (square & 136) {
              continue;
            }
            const color = this._turn;
            if (this._board[square]?.color === color && this._board[square]?.type === PAWN) {
              this._makeMove({
                color,
                from: square,
                to: this._epSquare,
                piece: PAWN,
                captured: PAWN,
                flags: BITS.EP_CAPTURE
              });
              const isLegal = !this._isKingAttacked(color);
              this._undoMove();
              if (isLegal) {
                epSquare = algebraic(this._epSquare);
                break;
              }
            }
          }
        }
      }
      return [
        fen,
        this._turn,
        castling,
        epSquare,
        this._halfMoves,
        this._moveNumber
      ].join(" ");
    }
    _pieceKey(i) {
      if (!this._board[i]) {
        return 0n;
      }
      const { color, type } = this._board[i];
      const colorIndex = {
        w: 0,
        b: 1
      }[color];
      const typeIndex = {
        p: 0,
        n: 1,
        b: 2,
        r: 3,
        q: 4,
        k: 5
      }[type];
      return PIECE_KEYS[colorIndex][typeIndex][i];
    }
    _epKey() {
      return this._epSquare === EMPTY ? 0n : EP_KEYS[this._epSquare & 7];
    }
    _castlingKey() {
      const index = this._castling.w >> 5 | this._castling.b >> 3;
      return CASTLING_KEYS[index];
    }
    _computeHash() {
      let hash = 0n;
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        if (i & 136) {
          i += 7;
          continue;
        }
        if (this._board[i]) {
          hash ^= this._pieceKey(i);
        }
      }
      hash ^= this._epKey();
      hash ^= this._castlingKey();
      if (this._turn === "b") {
        hash ^= SIDE_KEY;
      }
      return hash;
    }
    /*
     * Called when the initial board setup is changed with put() or remove().
     * modifies the SetUp and FEN properties of the header object. If the FEN
     * is equal to the default position, the SetUp and FEN are deleted the setup
     * is only updated if history.length is zero, ie moves haven't been made.
     */
    _updateSetup(fen) {
      if (this._history.length > 0)
        return;
      if (fen !== DEFAULT_POSITION) {
        this._header["SetUp"] = "1";
        this._header["FEN"] = fen;
      } else {
        this._header["SetUp"] = null;
        this._header["FEN"] = null;
      }
    }
    reset() {
      this.load(DEFAULT_POSITION);
    }
    get(square) {
      return this._board[Ox88[square]];
    }
    findPiece(piece) {
      const squares = [];
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        if (i & 136) {
          i += 7;
          continue;
        }
        if (!this._board[i] || this._board[i]?.color !== piece.color) {
          continue;
        }
        if (this._board[i].color === piece.color && this._board[i].type === piece.type) {
          squares.push(algebraic(i));
        }
      }
      return squares;
    }
    put({ type, color }, square) {
      if (this._put({ type, color }, square)) {
        this._updateCastlingRights();
        this._updateEnPassantSquare();
        this._updateSetup(this.fen());
        return true;
      }
      return false;
    }
    _set(sq, piece) {
      this._hash ^= this._pieceKey(sq);
      this._board[sq] = piece;
      this._hash ^= this._pieceKey(sq);
    }
    _put({ type, color }, square) {
      if (SYMBOLS.indexOf(type.toLowerCase()) === -1) {
        return false;
      }
      if (!(square in Ox88)) {
        return false;
      }
      const sq = Ox88[square];
      if (type == KING && !(this._kings[color] == EMPTY || this._kings[color] == sq)) {
        return false;
      }
      const currentPieceOnSquare = this._board[sq];
      if (currentPieceOnSquare && currentPieceOnSquare.type === KING) {
        this._kings[currentPieceOnSquare.color] = EMPTY;
      }
      this._set(sq, { type, color });
      if (type === KING) {
        this._kings[color] = sq;
      }
      return true;
    }
    _clear(sq) {
      this._hash ^= this._pieceKey(sq);
      delete this._board[sq];
    }
    remove(square) {
      const piece = this.get(square);
      this._clear(Ox88[square]);
      if (piece && piece.type === KING) {
        this._kings[piece.color] = EMPTY;
      }
      this._updateCastlingRights();
      this._updateEnPassantSquare();
      this._updateSetup(this.fen());
      return piece;
    }
    _updateCastlingRights() {
      this._hash ^= this._castlingKey();
      const whiteKingInPlace = this._board[Ox88.e1]?.type === KING && this._board[Ox88.e1]?.color === WHITE;
      const blackKingInPlace = this._board[Ox88.e8]?.type === KING && this._board[Ox88.e8]?.color === BLACK;
      if (!whiteKingInPlace || this._board[Ox88.a1]?.type !== ROOK || this._board[Ox88.a1]?.color !== WHITE) {
        this._castling.w &= -65;
      }
      if (!whiteKingInPlace || this._board[Ox88.h1]?.type !== ROOK || this._board[Ox88.h1]?.color !== WHITE) {
        this._castling.w &= -33;
      }
      if (!blackKingInPlace || this._board[Ox88.a8]?.type !== ROOK || this._board[Ox88.a8]?.color !== BLACK) {
        this._castling.b &= -65;
      }
      if (!blackKingInPlace || this._board[Ox88.h8]?.type !== ROOK || this._board[Ox88.h8]?.color !== BLACK) {
        this._castling.b &= -33;
      }
      this._hash ^= this._castlingKey();
    }
    _updateEnPassantSquare() {
      if (this._epSquare === EMPTY) {
        return;
      }
      const startSquare = this._epSquare + (this._turn === WHITE ? -16 : 16);
      const currentSquare = this._epSquare + (this._turn === WHITE ? 16 : -16);
      const attackers = [currentSquare + 1, currentSquare - 1];
      if (this._board[startSquare] !== null || this._board[this._epSquare] !== null || this._board[currentSquare]?.color !== swapColor(this._turn) || this._board[currentSquare]?.type !== PAWN) {
        this._hash ^= this._epKey();
        this._epSquare = EMPTY;
        return;
      }
      const canCapture = (square) => !(square & 136) && this._board[square]?.color === this._turn && this._board[square]?.type === PAWN;
      if (!attackers.some(canCapture)) {
        this._hash ^= this._epKey();
        this._epSquare = EMPTY;
      }
    }
    _attacked(color, square, verbose) {
      const attackers = [];
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        if (i & 136) {
          i += 7;
          continue;
        }
        if (this._board[i] === void 0 || this._board[i].color !== color) {
          continue;
        }
        const piece = this._board[i];
        const difference = i - square;
        if (difference === 0) {
          continue;
        }
        const index = difference + 119;
        if (ATTACKS[index] & PIECE_MASKS[piece.type]) {
          if (piece.type === PAWN) {
            if (difference > 0 && piece.color === WHITE || difference <= 0 && piece.color === BLACK) {
              if (!verbose) {
                return true;
              } else {
                attackers.push(algebraic(i));
              }
            }
            continue;
          }
          if (piece.type === "n" || piece.type === "k") {
            if (!verbose) {
              return true;
            } else {
              attackers.push(algebraic(i));
              continue;
            }
          }
          const offset = RAYS[index];
          let j = i + offset;
          let blocked = false;
          while (j !== square) {
            if (this._board[j] != null) {
              blocked = true;
              break;
            }
            j += offset;
          }
          if (!blocked) {
            if (!verbose) {
              return true;
            } else {
              attackers.push(algebraic(i));
              continue;
            }
          }
        }
      }
      if (verbose) {
        return attackers;
      } else {
        return false;
      }
    }
    attackers(square, attackedBy) {
      if (!attackedBy) {
        return this._attacked(this._turn, Ox88[square], true);
      } else {
        return this._attacked(attackedBy, Ox88[square], true);
      }
    }
    _isKingAttacked(color) {
      const square = this._kings[color];
      return square === -1 ? false : this._attacked(swapColor(color), square);
    }
    hash() {
      return this._hash.toString(16);
    }
    isAttacked(square, attackedBy) {
      return this._attacked(attackedBy, Ox88[square]);
    }
    isCheck() {
      return this._isKingAttacked(this._turn);
    }
    inCheck() {
      return this.isCheck();
    }
    isCheckmate() {
      return this.isCheck() && this._moves().length === 0;
    }
    isStalemate() {
      return !this.isCheck() && this._moves().length === 0;
    }
    isInsufficientMaterial() {
      const pieces = {
        b: 0,
        n: 0,
        r: 0,
        q: 0,
        k: 0,
        p: 0
      };
      const bishops = [];
      let numPieces = 0;
      let squareColor = 0;
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        squareColor = (squareColor + 1) % 2;
        if (i & 136) {
          i += 7;
          continue;
        }
        const piece = this._board[i];
        if (piece) {
          pieces[piece.type] = piece.type in pieces ? pieces[piece.type] + 1 : 1;
          if (piece.type === BISHOP) {
            bishops.push(squareColor);
          }
          numPieces++;
        }
      }
      if (numPieces === 2) {
        return true;
      } else if (
        // k vs. kn .... or .... k vs. kb
        numPieces === 3 && (pieces[BISHOP] === 1 || pieces[KNIGHT] === 1)
      ) {
        return true;
      } else if (numPieces === pieces[BISHOP] + 2) {
        let sum = 0;
        const len = bishops.length;
        for (let i = 0; i < len; i++) {
          sum += bishops[i];
        }
        if (sum === 0 || sum === len) {
          return true;
        }
      }
      return false;
    }
    isThreefoldRepetition() {
      return this._getPositionCount(this._hash) >= 3;
    }
    isDrawByFiftyMoves() {
      return this._halfMoves >= 100;
    }
    isDraw() {
      return this.isDrawByFiftyMoves() || this.isStalemate() || this.isInsufficientMaterial() || this.isThreefoldRepetition();
    }
    isGameOver() {
      return this.isCheckmate() || this.isDraw();
    }
    moves({ verbose = false, square = void 0, piece = void 0 } = {}) {
      const moves = this._moves({ square, piece });
      if (verbose) {
        return moves.map((move) => new Move(this, move));
      } else {
        return moves.map((move) => this._moveToSan(move, moves));
      }
    }
    _moves({ legal = true, piece = void 0, square = void 0 } = {}) {
      const forSquare = square ? square.toLowerCase() : void 0;
      const forPiece = piece?.toLowerCase();
      const moves = [];
      const us = this._turn;
      const them = swapColor(us);
      let firstSquare = Ox88.a8;
      let lastSquare = Ox88.h1;
      let singleSquare = false;
      if (forSquare) {
        if (!(forSquare in Ox88)) {
          return [];
        } else {
          firstSquare = lastSquare = Ox88[forSquare];
          singleSquare = true;
        }
      }
      for (let from = firstSquare; from <= lastSquare; from++) {
        if (from & 136) {
          from += 7;
          continue;
        }
        if (!this._board[from] || this._board[from].color === them) {
          continue;
        }
        const { type } = this._board[from];
        let to;
        if (type === PAWN) {
          if (forPiece && forPiece !== type)
            continue;
          to = from + PAWN_OFFSETS[us][0];
          if (!this._board[to]) {
            addMove(moves, us, from, to, PAWN);
            to = from + PAWN_OFFSETS[us][1];
            if (SECOND_RANK[us] === rank(from) && !this._board[to]) {
              addMove(moves, us, from, to, PAWN, void 0, BITS.BIG_PAWN);
            }
          }
          for (let j = 2; j < 4; j++) {
            to = from + PAWN_OFFSETS[us][j];
            if (to & 136)
              continue;
            if (this._board[to]?.color === them) {
              addMove(moves, us, from, to, PAWN, this._board[to].type, BITS.CAPTURE);
            } else if (to === this._epSquare) {
              addMove(moves, us, from, to, PAWN, PAWN, BITS.EP_CAPTURE);
            }
          }
        } else {
          if (forPiece && forPiece !== type)
            continue;
          for (let j = 0, len = PIECE_OFFSETS[type].length; j < len; j++) {
            const offset = PIECE_OFFSETS[type][j];
            to = from;
            while (true) {
              to += offset;
              if (to & 136)
                break;
              if (!this._board[to]) {
                addMove(moves, us, from, to, type);
              } else {
                if (this._board[to].color === us)
                  break;
                addMove(moves, us, from, to, type, this._board[to].type, BITS.CAPTURE);
                break;
              }
              if (type === KNIGHT || type === KING)
                break;
            }
          }
        }
      }
      if (forPiece === void 0 || forPiece === KING) {
        if (!singleSquare || lastSquare === this._kings[us]) {
          if (this._castling[us] & BITS.KSIDE_CASTLE) {
            const castlingFrom = this._kings[us];
            const castlingTo = castlingFrom + 2;
            if (!this._board[castlingFrom + 1] && !this._board[castlingTo] && !this._attacked(them, this._kings[us]) && !this._attacked(them, castlingFrom + 1) && !this._attacked(them, castlingTo)) {
              addMove(moves, us, this._kings[us], castlingTo, KING, void 0, BITS.KSIDE_CASTLE);
            }
          }
          if (this._castling[us] & BITS.QSIDE_CASTLE) {
            const castlingFrom = this._kings[us];
            const castlingTo = castlingFrom - 2;
            if (!this._board[castlingFrom - 1] && !this._board[castlingFrom - 2] && !this._board[castlingFrom - 3] && !this._attacked(them, this._kings[us]) && !this._attacked(them, castlingFrom - 1) && !this._attacked(them, castlingTo)) {
              addMove(moves, us, this._kings[us], castlingTo, KING, void 0, BITS.QSIDE_CASTLE);
            }
          }
        }
      }
      if (!legal || this._kings[us] === -1) {
        return moves;
      }
      const legalMoves = [];
      for (let i = 0, len = moves.length; i < len; i++) {
        this._makeMove(moves[i]);
        if (!this._isKingAttacked(us)) {
          legalMoves.push(moves[i]);
        }
        this._undoMove();
      }
      return legalMoves;
    }
    move(move, { strict = false } = {}) {
      let moveObj = null;
      if (typeof move === "string") {
        moveObj = this._moveFromSan(move, strict);
      } else if (move === null) {
        moveObj = this._moveFromSan(SAN_NULLMOVE, strict);
      } else if (typeof move === "object") {
        const moves = this._moves();
        for (let i = 0, len = moves.length; i < len; i++) {
          if (move.from === algebraic(moves[i].from) && move.to === algebraic(moves[i].to) && (!("promotion" in moves[i]) || move.promotion === moves[i].promotion)) {
            moveObj = moves[i];
            break;
          }
        }
      }
      if (!moveObj) {
        if (typeof move === "string") {
          throw new Error(`Invalid move: ${move}`);
        } else {
          throw new Error(`Invalid move: ${JSON.stringify(move)}`);
        }
      }
      if (this.isCheck() && moveObj.flags & BITS.NULL_MOVE) {
        throw new Error("Null move not allowed when in check");
      }
      const prettyMove = new Move(this, moveObj);
      this._makeMove(moveObj);
      this._incPositionCount();
      return prettyMove;
    }
    _push(move) {
      this._history.push({
        move,
        kings: { b: this._kings.b, w: this._kings.w },
        turn: this._turn,
        castling: { b: this._castling.b, w: this._castling.w },
        epSquare: this._epSquare,
        halfMoves: this._halfMoves,
        moveNumber: this._moveNumber
      });
    }
    _movePiece(from, to) {
      this._hash ^= this._pieceKey(from);
      this._board[to] = this._board[from];
      delete this._board[from];
      this._hash ^= this._pieceKey(to);
    }
    _makeMove(move) {
      const us = this._turn;
      const them = swapColor(us);
      this._push(move);
      if (move.flags & BITS.NULL_MOVE) {
        if (us === BLACK) {
          this._moveNumber++;
        }
        this._halfMoves++;
        this._turn = them;
        this._epSquare = EMPTY;
        return;
      }
      this._hash ^= this._epKey();
      this._hash ^= this._castlingKey();
      if (move.captured) {
        this._hash ^= this._pieceKey(move.to);
      }
      this._movePiece(move.from, move.to);
      if (move.flags & BITS.EP_CAPTURE) {
        if (this._turn === BLACK) {
          this._clear(move.to - 16);
        } else {
          this._clear(move.to + 16);
        }
      }
      if (move.promotion) {
        this._clear(move.to);
        this._set(move.to, { type: move.promotion, color: us });
      }
      if (this._board[move.to].type === KING) {
        this._kings[us] = move.to;
        if (move.flags & BITS.KSIDE_CASTLE) {
          const castlingTo = move.to - 1;
          const castlingFrom = move.to + 1;
          this._movePiece(castlingFrom, castlingTo);
        } else if (move.flags & BITS.QSIDE_CASTLE) {
          const castlingTo = move.to + 1;
          const castlingFrom = move.to - 2;
          this._movePiece(castlingFrom, castlingTo);
        }
        this._castling[us] = 0;
      }
      if (this._castling[us]) {
        for (let i = 0, len = ROOKS[us].length; i < len; i++) {
          if (move.from === ROOKS[us][i].square && this._castling[us] & ROOKS[us][i].flag) {
            this._castling[us] ^= ROOKS[us][i].flag;
            break;
          }
        }
      }
      if (this._castling[them]) {
        for (let i = 0, len = ROOKS[them].length; i < len; i++) {
          if (move.to === ROOKS[them][i].square && this._castling[them] & ROOKS[them][i].flag) {
            this._castling[them] ^= ROOKS[them][i].flag;
            break;
          }
        }
      }
      this._hash ^= this._castlingKey();
      if (move.flags & BITS.BIG_PAWN) {
        let epSquare;
        if (us === BLACK) {
          epSquare = move.to - 16;
        } else {
          epSquare = move.to + 16;
        }
        if (!(move.to - 1 & 136) && this._board[move.to - 1]?.type === PAWN && this._board[move.to - 1]?.color === them || !(move.to + 1 & 136) && this._board[move.to + 1]?.type === PAWN && this._board[move.to + 1]?.color === them) {
          this._epSquare = epSquare;
          this._hash ^= this._epKey();
        } else {
          this._epSquare = EMPTY;
        }
      } else {
        this._epSquare = EMPTY;
      }
      if (move.piece === PAWN) {
        this._halfMoves = 0;
      } else if (move.flags & (BITS.CAPTURE | BITS.EP_CAPTURE)) {
        this._halfMoves = 0;
      } else {
        this._halfMoves++;
      }
      if (us === BLACK) {
        this._moveNumber++;
      }
      this._turn = them;
      this._hash ^= SIDE_KEY;
    }
    undo() {
      const hash = this._hash;
      const move = this._undoMove();
      if (move) {
        const prettyMove = new Move(this, move);
        this._decPositionCount(hash);
        return prettyMove;
      }
      return null;
    }
    _undoMove() {
      const old = this._history.pop();
      if (old === void 0) {
        return null;
      }
      this._hash ^= this._epKey();
      this._hash ^= this._castlingKey();
      const move = old.move;
      this._kings = old.kings;
      this._turn = old.turn;
      this._castling = old.castling;
      this._epSquare = old.epSquare;
      this._halfMoves = old.halfMoves;
      this._moveNumber = old.moveNumber;
      this._hash ^= this._epKey();
      this._hash ^= this._castlingKey();
      this._hash ^= SIDE_KEY;
      const us = this._turn;
      const them = swapColor(us);
      if (move.flags & BITS.NULL_MOVE) {
        return move;
      }
      this._movePiece(move.to, move.from);
      if (move.piece) {
        this._clear(move.from);
        this._set(move.from, { type: move.piece, color: us });
      }
      if (move.captured) {
        if (move.flags & BITS.EP_CAPTURE) {
          let index;
          if (us === BLACK) {
            index = move.to - 16;
          } else {
            index = move.to + 16;
          }
          this._set(index, { type: PAWN, color: them });
        } else {
          this._set(move.to, { type: move.captured, color: them });
        }
      }
      if (move.flags & (BITS.KSIDE_CASTLE | BITS.QSIDE_CASTLE)) {
        let castlingTo, castlingFrom;
        if (move.flags & BITS.KSIDE_CASTLE) {
          castlingTo = move.to + 1;
          castlingFrom = move.to - 1;
        } else {
          castlingTo = move.to - 2;
          castlingFrom = move.to + 1;
        }
        this._movePiece(castlingFrom, castlingTo);
      }
      return move;
    }
    pgn({ newline = "\n", maxWidth = 0 } = {}) {
      const result = [];
      let headerExists = false;
      for (const i in this._header) {
        const headerTag = this._header[i];
        if (headerTag)
          result.push(`[${i} "${this._header[i]}"]` + newline);
        headerExists = true;
      }
      if (headerExists && this._history.length) {
        result.push(newline);
      }
      const appendComment = (moveString2) => {
        const comment = this._comments[this.fen()];
        if (typeof comment !== "undefined") {
          const delimiter = moveString2.length > 0 ? " " : "";
          moveString2 = `${moveString2}${delimiter}{${comment}}`;
        }
        return moveString2;
      };
      const reversedHistory = [];
      while (this._history.length > 0) {
        reversedHistory.push(this._undoMove());
      }
      const moves = [];
      let moveString = "";
      if (reversedHistory.length === 0) {
        moves.push(appendComment(""));
      }
      while (reversedHistory.length > 0) {
        moveString = appendComment(moveString);
        const move = reversedHistory.pop();
        if (!move) {
          break;
        }
        if (!this._history.length && move.color === "b") {
          const prefix = `${this._moveNumber}. ...`;
          moveString = moveString ? `${moveString} ${prefix}` : prefix;
        } else if (move.color === "w") {
          if (moveString.length) {
            moves.push(moveString);
          }
          moveString = this._moveNumber + ".";
        }
        moveString = moveString + " " + this._moveToSan(move, this._moves({ legal: true }));
        this._makeMove(move);
      }
      if (moveString.length) {
        moves.push(appendComment(moveString));
      }
      moves.push(this._header.Result || "*");
      if (maxWidth === 0) {
        return result.join("") + moves.join(" ");
      }
      const strip = function() {
        if (result.length > 0 && result[result.length - 1] === " ") {
          result.pop();
          return true;
        }
        return false;
      };
      const wrapComment = function(width, move) {
        for (const token of move.split(" ")) {
          if (!token) {
            continue;
          }
          if (width + token.length > maxWidth) {
            while (strip()) {
              width--;
            }
            result.push(newline);
            width = 0;
          }
          result.push(token);
          width += token.length;
          result.push(" ");
          width++;
        }
        if (strip()) {
          width--;
        }
        return width;
      };
      let currentWidth = 0;
      for (let i = 0; i < moves.length; i++) {
        if (currentWidth + moves[i].length > maxWidth) {
          if (moves[i].includes("{")) {
            currentWidth = wrapComment(currentWidth, moves[i]);
            continue;
          }
        }
        if (currentWidth + moves[i].length > maxWidth && i !== 0) {
          if (result[result.length - 1] === " ") {
            result.pop();
          }
          result.push(newline);
          currentWidth = 0;
        } else if (i !== 0) {
          result.push(" ");
          currentWidth++;
        }
        result.push(moves[i]);
        currentWidth += moves[i].length;
      }
      return result.join("");
    }
    /**
     * @deprecated Use `setHeader` and `getHeaders` instead. This method will return null header tags (which is not what you want)
     */
    header(...args) {
      for (let i = 0; i < args.length; i += 2) {
        if (typeof args[i] === "string" && typeof args[i + 1] === "string") {
          this._header[args[i]] = args[i + 1];
        }
      }
      return this._header;
    }
    // TODO: value validation per spec
    setHeader(key, value) {
      this._header[key] = value ?? SEVEN_TAG_ROSTER[key] ?? null;
      return this.getHeaders();
    }
    removeHeader(key) {
      if (key in this._header) {
        this._header[key] = SEVEN_TAG_ROSTER[key] || null;
        return true;
      }
      return false;
    }
    // return only non-null headers (omit placemarker nulls)
    getHeaders() {
      const nonNullHeaders = {};
      for (const [key, value] of Object.entries(this._header)) {
        if (value !== null) {
          nonNullHeaders[key] = value;
        }
      }
      return nonNullHeaders;
    }
    loadPgn(pgn2, { strict = false, newlineChar = "\r?\n" } = {}) {
      if (newlineChar !== "\r?\n") {
        pgn2 = pgn2.replace(new RegExp(newlineChar, "g"), "\n");
      }
      const parsedPgn = peg$parse(pgn2);
      this.reset();
      const headers = parsedPgn.headers;
      let fen = "";
      for (const key in headers) {
        if (key.toLowerCase() === "fen") {
          fen = headers[key];
        }
        this.header(key, headers[key]);
      }
      if (!strict) {
        if (fen) {
          this.load(fen, { preserveHeaders: true });
        }
      } else {
        if (headers["SetUp"] === "1") {
          if (!("FEN" in headers)) {
            throw new Error("Invalid PGN: FEN tag must be supplied with SetUp tag");
          }
          this.load(headers["FEN"], { preserveHeaders: true });
        }
      }
      let node2 = parsedPgn.root;
      while (node2) {
        if (node2.move) {
          const move = this._moveFromSan(node2.move, strict);
          if (move == null) {
            throw new Error(`Invalid move in PGN: ${node2.move}`);
          } else {
            this._makeMove(move);
            this._incPositionCount();
          }
        }
        if (node2.comment !== void 0) {
          this._comments[this.fen()] = node2.comment;
        }
        node2 = node2.variations[0];
      }
      const result = parsedPgn.result;
      if (result && Object.keys(this._header).length && this._header["Result"] !== result) {
        this.setHeader("Result", result);
      }
    }
    /*
     * Convert a move from 0x88 coordinates to Standard Algebraic Notation
     * (SAN)
     *
     * @param {boolean} strict Use the strict SAN parser. It will throw errors
     * on overly disambiguated moves (see below):
     *
     * r1bqkbnr/ppp2ppp/2n5/1B1pP3/4P3/8/PPPP2PP/RNBQK1NR b KQkq - 2 4
     * 4. ... Nge7 is overly disambiguated because the knight on c6 is pinned
     * 4. ... Ne7 is technically the valid SAN
     */
    _moveToSan(move, moves) {
      let output = "";
      if (move.flags & BITS.KSIDE_CASTLE) {
        output = "O-O";
      } else if (move.flags & BITS.QSIDE_CASTLE) {
        output = "O-O-O";
      } else if (move.flags & BITS.NULL_MOVE) {
        return SAN_NULLMOVE;
      } else {
        if (move.piece !== PAWN) {
          const disambiguator = getDisambiguator(move, moves);
          output += move.piece.toUpperCase() + disambiguator;
        }
        if (move.flags & (BITS.CAPTURE | BITS.EP_CAPTURE)) {
          if (move.piece === PAWN) {
            output += algebraic(move.from)[0];
          }
          output += "x";
        }
        output += algebraic(move.to);
        if (move.promotion) {
          output += "=" + move.promotion.toUpperCase();
        }
      }
      this._makeMove(move);
      if (this.isCheck()) {
        if (this.isCheckmate()) {
          output += "#";
        } else {
          output += "+";
        }
      }
      this._undoMove();
      return output;
    }
    // convert a move from Standard Algebraic Notation (SAN) to 0x88 coordinates
    _moveFromSan(move, strict = false) {
      let cleanMove = strippedSan(move);
      if (!strict) {
        if (cleanMove === "0-0") {
          cleanMove = "O-O";
        } else if (cleanMove === "0-0-0") {
          cleanMove = "O-O-O";
        }
      }
      if (cleanMove == SAN_NULLMOVE) {
        const res = {
          color: this._turn,
          from: 0,
          to: 0,
          piece: "k",
          flags: BITS.NULL_MOVE
        };
        return res;
      }
      let pieceType = inferPieceType(cleanMove);
      let moves = this._moves({ legal: true, piece: pieceType });
      for (let i = 0, len = moves.length; i < len; i++) {
        if (cleanMove === strippedSan(this._moveToSan(moves[i], moves))) {
          return moves[i];
        }
      }
      if (strict) {
        return null;
      }
      let piece = void 0;
      let matches = void 0;
      let from = void 0;
      let to = void 0;
      let promotion = void 0;
      let overlyDisambiguated = false;
      matches = cleanMove.match(/([pnbrqkPNBRQK])?([a-h][1-8])x?-?([a-h][1-8])([qrbnQRBN])?/);
      if (matches) {
        piece = matches[1];
        from = matches[2];
        to = matches[3];
        promotion = matches[4];
        if (from.length == 1) {
          overlyDisambiguated = true;
        }
      } else {
        matches = cleanMove.match(/([pnbrqkPNBRQK])?([a-h]?[1-8]?)x?-?([a-h][1-8])([qrbnQRBN])?/);
        if (matches) {
          piece = matches[1];
          from = matches[2];
          to = matches[3];
          promotion = matches[4];
          if (from.length == 1) {
            overlyDisambiguated = true;
          }
        }
      }
      pieceType = inferPieceType(cleanMove);
      moves = this._moves({
        legal: true,
        piece: piece ? piece : pieceType
      });
      if (!to) {
        return null;
      }
      for (let i = 0, len = moves.length; i < len; i++) {
        if (!from) {
          if (cleanMove === strippedSan(this._moveToSan(moves[i], moves)).replace("x", "")) {
            return moves[i];
          }
        } else if ((!piece || piece.toLowerCase() == moves[i].piece) && Ox88[from] == moves[i].from && Ox88[to] == moves[i].to && (!promotion || promotion.toLowerCase() == moves[i].promotion)) {
          return moves[i];
        } else if (overlyDisambiguated) {
          const square = algebraic(moves[i].from);
          if ((!piece || piece.toLowerCase() == moves[i].piece) && Ox88[to] == moves[i].to && (from == square[0] || from == square[1]) && (!promotion || promotion.toLowerCase() == moves[i].promotion)) {
            return moves[i];
          }
        }
      }
      return null;
    }
    ascii() {
      let s = "   +------------------------+\n";
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        if (file(i) === 0) {
          s += " " + "87654321"[rank(i)] + " |";
        }
        if (this._board[i]) {
          const piece = this._board[i].type;
          const color = this._board[i].color;
          const symbol = color === WHITE ? piece.toUpperCase() : piece.toLowerCase();
          s += " " + symbol + " ";
        } else {
          s += " . ";
        }
        if (i + 1 & 136) {
          s += "|\n";
          i += 8;
        }
      }
      s += "   +------------------------+\n";
      s += "     a  b  c  d  e  f  g  h";
      return s;
    }
    perft(depth) {
      const moves = this._moves({ legal: false });
      let nodes = 0;
      const color = this._turn;
      for (let i = 0, len = moves.length; i < len; i++) {
        this._makeMove(moves[i]);
        if (!this._isKingAttacked(color)) {
          if (depth - 1 > 0) {
            nodes += this.perft(depth - 1);
          } else {
            nodes++;
          }
        }
        this._undoMove();
      }
      return nodes;
    }
    setTurn(color) {
      if (this._turn == color) {
        return false;
      }
      this.move("--");
      return true;
    }
    turn() {
      return this._turn;
    }
    board() {
      const output = [];
      let row = [];
      for (let i = Ox88.a8; i <= Ox88.h1; i++) {
        if (this._board[i] == null) {
          row.push(null);
        } else {
          row.push({
            square: algebraic(i),
            type: this._board[i].type,
            color: this._board[i].color
          });
        }
        if (i + 1 & 136) {
          output.push(row);
          row = [];
          i += 8;
        }
      }
      return output;
    }
    squareColor(square) {
      if (square in Ox88) {
        const sq = Ox88[square];
        return (rank(sq) + file(sq)) % 2 === 0 ? "light" : "dark";
      }
      return null;
    }
    history({ verbose = false } = {}) {
      const reversedHistory = [];
      const moveHistory = [];
      while (this._history.length > 0) {
        reversedHistory.push(this._undoMove());
      }
      while (true) {
        const move = reversedHistory.pop();
        if (!move) {
          break;
        }
        if (verbose) {
          moveHistory.push(new Move(this, move));
        } else {
          moveHistory.push(this._moveToSan(move, this._moves()));
        }
        this._makeMove(move);
      }
      return moveHistory;
    }
    /*
     * Keeps track of position occurrence counts for the purpose of repetition
     * checking. Old positions are removed from the map if their counts are reduced to 0.
     */
    _getPositionCount(hash) {
      return this._positionCount.get(hash) ?? 0;
    }
    _incPositionCount() {
      this._positionCount.set(this._hash, (this._positionCount.get(this._hash) ?? 0) + 1);
    }
    _decPositionCount(hash) {
      const currentCount = this._positionCount.get(hash) ?? 0;
      if (currentCount === 1) {
        this._positionCount.delete(hash);
      } else {
        this._positionCount.set(hash, currentCount - 1);
      }
    }
    _pruneComments() {
      const reversedHistory = [];
      const currentComments = {};
      const copyComment = (fen) => {
        if (fen in this._comments) {
          currentComments[fen] = this._comments[fen];
        }
      };
      while (this._history.length > 0) {
        reversedHistory.push(this._undoMove());
      }
      copyComment(this.fen());
      while (true) {
        const move = reversedHistory.pop();
        if (!move) {
          break;
        }
        this._makeMove(move);
        copyComment(this.fen());
      }
      this._comments = currentComments;
    }
    getComment() {
      return this._comments[this.fen()];
    }
    setComment(comment) {
      this._comments[this.fen()] = comment.replace("{", "[").replace("}", "]");
    }
    /**
     * @deprecated Renamed to `removeComment` for consistency
     */
    deleteComment() {
      return this.removeComment();
    }
    removeComment() {
      const comment = this._comments[this.fen()];
      delete this._comments[this.fen()];
      return comment;
    }
    getComments() {
      this._pruneComments();
      return Object.keys(this._comments).map((fen) => {
        return { fen, comment: this._comments[fen] };
      });
    }
    /**
     * @deprecated Renamed to `removeComments` for consistency
     */
    deleteComments() {
      return this.removeComments();
    }
    removeComments() {
      this._pruneComments();
      return Object.keys(this._comments).map((fen) => {
        const comment = this._comments[fen];
        delete this._comments[fen];
        return { fen, comment };
      });
    }
    setCastlingRights(color, rights) {
      for (const side of [KING, QUEEN]) {
        if (rights[side] !== void 0) {
          if (rights[side]) {
            this._castling[color] |= SIDES[side];
          } else {
            this._castling[color] &= ~SIDES[side];
          }
        }
      }
      this._updateCastlingRights();
      const result = this.getCastlingRights(color);
      return (rights[KING] === void 0 || rights[KING] === result[KING]) && (rights[QUEEN] === void 0 || rights[QUEEN] === result[QUEEN]);
    }
    getCastlingRights(color) {
      return {
        [KING]: (this._castling[color] & SIDES[KING]) !== 0,
        [QUEEN]: (this._castling[color] & SIDES[QUEEN]) !== 0
      };
    }
    moveNumber() {
      return this._moveNumber;
    }
  };

  // brain/maia/policyIndex.ts
  var POLICY_INDEX = [
    "a1b1",
    "a1c1",
    "a1d1",
    "a1e1",
    "a1f1",
    "a1g1",
    "a1h1",
    "a1a2",
    "a1b2",
    "a1c2",
    "a1a3",
    "a1b3",
    "a1c3",
    "a1a4",
    "a1d4",
    "a1a5",
    "a1e5",
    "a1a6",
    "a1f6",
    "a1a7",
    "a1g7",
    "a1a8",
    "a1h8",
    "b1a1",
    "b1c1",
    "b1d1",
    "b1e1",
    "b1f1",
    "b1g1",
    "b1h1",
    "b1a2",
    "b1b2",
    "b1c2",
    "b1d2",
    "b1a3",
    "b1b3",
    "b1c3",
    "b1d3",
    "b1b4",
    "b1e4",
    "b1b5",
    "b1f5",
    "b1b6",
    "b1g6",
    "b1b7",
    "b1h7",
    "b1b8",
    "c1a1",
    "c1b1",
    "c1d1",
    "c1e1",
    "c1f1",
    "c1g1",
    "c1h1",
    "c1a2",
    "c1b2",
    "c1c2",
    "c1d2",
    "c1e2",
    "c1a3",
    "c1b3",
    "c1c3",
    "c1d3",
    "c1e3",
    "c1c4",
    "c1f4",
    "c1c5",
    "c1g5",
    "c1c6",
    "c1h6",
    "c1c7",
    "c1c8",
    "d1a1",
    "d1b1",
    "d1c1",
    "d1e1",
    "d1f1",
    "d1g1",
    "d1h1",
    "d1b2",
    "d1c2",
    "d1d2",
    "d1e2",
    "d1f2",
    "d1b3",
    "d1c3",
    "d1d3",
    "d1e3",
    "d1f3",
    "d1a4",
    "d1d4",
    "d1g4",
    "d1d5",
    "d1h5",
    "d1d6",
    "d1d7",
    "d1d8",
    "e1a1",
    "e1b1",
    "e1c1",
    "e1d1",
    "e1f1",
    "e1g1",
    "e1h1",
    "e1c2",
    "e1d2",
    "e1e2",
    "e1f2",
    "e1g2",
    "e1c3",
    "e1d3",
    "e1e3",
    "e1f3",
    "e1g3",
    "e1b4",
    "e1e4",
    "e1h4",
    "e1a5",
    "e1e5",
    "e1e6",
    "e1e7",
    "e1e8",
    "f1a1",
    "f1b1",
    "f1c1",
    "f1d1",
    "f1e1",
    "f1g1",
    "f1h1",
    "f1d2",
    "f1e2",
    "f1f2",
    "f1g2",
    "f1h2",
    "f1d3",
    "f1e3",
    "f1f3",
    "f1g3",
    "f1h3",
    "f1c4",
    "f1f4",
    "f1b5",
    "f1f5",
    "f1a6",
    "f1f6",
    "f1f7",
    "f1f8",
    "g1a1",
    "g1b1",
    "g1c1",
    "g1d1",
    "g1e1",
    "g1f1",
    "g1h1",
    "g1e2",
    "g1f2",
    "g1g2",
    "g1h2",
    "g1e3",
    "g1f3",
    "g1g3",
    "g1h3",
    "g1d4",
    "g1g4",
    "g1c5",
    "g1g5",
    "g1b6",
    "g1g6",
    "g1a7",
    "g1g7",
    "g1g8",
    "h1a1",
    "h1b1",
    "h1c1",
    "h1d1",
    "h1e1",
    "h1f1",
    "h1g1",
    "h1f2",
    "h1g2",
    "h1h2",
    "h1f3",
    "h1g3",
    "h1h3",
    "h1e4",
    "h1h4",
    "h1d5",
    "h1h5",
    "h1c6",
    "h1h6",
    "h1b7",
    "h1h7",
    "h1a8",
    "h1h8",
    "a2a1",
    "a2b1",
    "a2c1",
    "a2b2",
    "a2c2",
    "a2d2",
    "a2e2",
    "a2f2",
    "a2g2",
    "a2h2",
    "a2a3",
    "a2b3",
    "a2c3",
    "a2a4",
    "a2b4",
    "a2c4",
    "a2a5",
    "a2d5",
    "a2a6",
    "a2e6",
    "a2a7",
    "a2f7",
    "a2a8",
    "a2g8",
    "b2a1",
    "b2b1",
    "b2c1",
    "b2d1",
    "b2a2",
    "b2c2",
    "b2d2",
    "b2e2",
    "b2f2",
    "b2g2",
    "b2h2",
    "b2a3",
    "b2b3",
    "b2c3",
    "b2d3",
    "b2a4",
    "b2b4",
    "b2c4",
    "b2d4",
    "b2b5",
    "b2e5",
    "b2b6",
    "b2f6",
    "b2b7",
    "b2g7",
    "b2b8",
    "b2h8",
    "c2a1",
    "c2b1",
    "c2c1",
    "c2d1",
    "c2e1",
    "c2a2",
    "c2b2",
    "c2d2",
    "c2e2",
    "c2f2",
    "c2g2",
    "c2h2",
    "c2a3",
    "c2b3",
    "c2c3",
    "c2d3",
    "c2e3",
    "c2a4",
    "c2b4",
    "c2c4",
    "c2d4",
    "c2e4",
    "c2c5",
    "c2f5",
    "c2c6",
    "c2g6",
    "c2c7",
    "c2h7",
    "c2c8",
    "d2b1",
    "d2c1",
    "d2d1",
    "d2e1",
    "d2f1",
    "d2a2",
    "d2b2",
    "d2c2",
    "d2e2",
    "d2f2",
    "d2g2",
    "d2h2",
    "d2b3",
    "d2c3",
    "d2d3",
    "d2e3",
    "d2f3",
    "d2b4",
    "d2c4",
    "d2d4",
    "d2e4",
    "d2f4",
    "d2a5",
    "d2d5",
    "d2g5",
    "d2d6",
    "d2h6",
    "d2d7",
    "d2d8",
    "e2c1",
    "e2d1",
    "e2e1",
    "e2f1",
    "e2g1",
    "e2a2",
    "e2b2",
    "e2c2",
    "e2d2",
    "e2f2",
    "e2g2",
    "e2h2",
    "e2c3",
    "e2d3",
    "e2e3",
    "e2f3",
    "e2g3",
    "e2c4",
    "e2d4",
    "e2e4",
    "e2f4",
    "e2g4",
    "e2b5",
    "e2e5",
    "e2h5",
    "e2a6",
    "e2e6",
    "e2e7",
    "e2e8",
    "f2d1",
    "f2e1",
    "f2f1",
    "f2g1",
    "f2h1",
    "f2a2",
    "f2b2",
    "f2c2",
    "f2d2",
    "f2e2",
    "f2g2",
    "f2h2",
    "f2d3",
    "f2e3",
    "f2f3",
    "f2g3",
    "f2h3",
    "f2d4",
    "f2e4",
    "f2f4",
    "f2g4",
    "f2h4",
    "f2c5",
    "f2f5",
    "f2b6",
    "f2f6",
    "f2a7",
    "f2f7",
    "f2f8",
    "g2e1",
    "g2f1",
    "g2g1",
    "g2h1",
    "g2a2",
    "g2b2",
    "g2c2",
    "g2d2",
    "g2e2",
    "g2f2",
    "g2h2",
    "g2e3",
    "g2f3",
    "g2g3",
    "g2h3",
    "g2e4",
    "g2f4",
    "g2g4",
    "g2h4",
    "g2d5",
    "g2g5",
    "g2c6",
    "g2g6",
    "g2b7",
    "g2g7",
    "g2a8",
    "g2g8",
    "h2f1",
    "h2g1",
    "h2h1",
    "h2a2",
    "h2b2",
    "h2c2",
    "h2d2",
    "h2e2",
    "h2f2",
    "h2g2",
    "h2f3",
    "h2g3",
    "h2h3",
    "h2f4",
    "h2g4",
    "h2h4",
    "h2e5",
    "h2h5",
    "h2d6",
    "h2h6",
    "h2c7",
    "h2h7",
    "h2b8",
    "h2h8",
    "a3a1",
    "a3b1",
    "a3c1",
    "a3a2",
    "a3b2",
    "a3c2",
    "a3b3",
    "a3c3",
    "a3d3",
    "a3e3",
    "a3f3",
    "a3g3",
    "a3h3",
    "a3a4",
    "a3b4",
    "a3c4",
    "a3a5",
    "a3b5",
    "a3c5",
    "a3a6",
    "a3d6",
    "a3a7",
    "a3e7",
    "a3a8",
    "a3f8",
    "b3a1",
    "b3b1",
    "b3c1",
    "b3d1",
    "b3a2",
    "b3b2",
    "b3c2",
    "b3d2",
    "b3a3",
    "b3c3",
    "b3d3",
    "b3e3",
    "b3f3",
    "b3g3",
    "b3h3",
    "b3a4",
    "b3b4",
    "b3c4",
    "b3d4",
    "b3a5",
    "b3b5",
    "b3c5",
    "b3d5",
    "b3b6",
    "b3e6",
    "b3b7",
    "b3f7",
    "b3b8",
    "b3g8",
    "c3a1",
    "c3b1",
    "c3c1",
    "c3d1",
    "c3e1",
    "c3a2",
    "c3b2",
    "c3c2",
    "c3d2",
    "c3e2",
    "c3a3",
    "c3b3",
    "c3d3",
    "c3e3",
    "c3f3",
    "c3g3",
    "c3h3",
    "c3a4",
    "c3b4",
    "c3c4",
    "c3d4",
    "c3e4",
    "c3a5",
    "c3b5",
    "c3c5",
    "c3d5",
    "c3e5",
    "c3c6",
    "c3f6",
    "c3c7",
    "c3g7",
    "c3c8",
    "c3h8",
    "d3b1",
    "d3c1",
    "d3d1",
    "d3e1",
    "d3f1",
    "d3b2",
    "d3c2",
    "d3d2",
    "d3e2",
    "d3f2",
    "d3a3",
    "d3b3",
    "d3c3",
    "d3e3",
    "d3f3",
    "d3g3",
    "d3h3",
    "d3b4",
    "d3c4",
    "d3d4",
    "d3e4",
    "d3f4",
    "d3b5",
    "d3c5",
    "d3d5",
    "d3e5",
    "d3f5",
    "d3a6",
    "d3d6",
    "d3g6",
    "d3d7",
    "d3h7",
    "d3d8",
    "e3c1",
    "e3d1",
    "e3e1",
    "e3f1",
    "e3g1",
    "e3c2",
    "e3d2",
    "e3e2",
    "e3f2",
    "e3g2",
    "e3a3",
    "e3b3",
    "e3c3",
    "e3d3",
    "e3f3",
    "e3g3",
    "e3h3",
    "e3c4",
    "e3d4",
    "e3e4",
    "e3f4",
    "e3g4",
    "e3c5",
    "e3d5",
    "e3e5",
    "e3f5",
    "e3g5",
    "e3b6",
    "e3e6",
    "e3h6",
    "e3a7",
    "e3e7",
    "e3e8",
    "f3d1",
    "f3e1",
    "f3f1",
    "f3g1",
    "f3h1",
    "f3d2",
    "f3e2",
    "f3f2",
    "f3g2",
    "f3h2",
    "f3a3",
    "f3b3",
    "f3c3",
    "f3d3",
    "f3e3",
    "f3g3",
    "f3h3",
    "f3d4",
    "f3e4",
    "f3f4",
    "f3g4",
    "f3h4",
    "f3d5",
    "f3e5",
    "f3f5",
    "f3g5",
    "f3h5",
    "f3c6",
    "f3f6",
    "f3b7",
    "f3f7",
    "f3a8",
    "f3f8",
    "g3e1",
    "g3f1",
    "g3g1",
    "g3h1",
    "g3e2",
    "g3f2",
    "g3g2",
    "g3h2",
    "g3a3",
    "g3b3",
    "g3c3",
    "g3d3",
    "g3e3",
    "g3f3",
    "g3h3",
    "g3e4",
    "g3f4",
    "g3g4",
    "g3h4",
    "g3e5",
    "g3f5",
    "g3g5",
    "g3h5",
    "g3d6",
    "g3g6",
    "g3c7",
    "g3g7",
    "g3b8",
    "g3g8",
    "h3f1",
    "h3g1",
    "h3h1",
    "h3f2",
    "h3g2",
    "h3h2",
    "h3a3",
    "h3b3",
    "h3c3",
    "h3d3",
    "h3e3",
    "h3f3",
    "h3g3",
    "h3f4",
    "h3g4",
    "h3h4",
    "h3f5",
    "h3g5",
    "h3h5",
    "h3e6",
    "h3h6",
    "h3d7",
    "h3h7",
    "h3c8",
    "h3h8",
    "a4a1",
    "a4d1",
    "a4a2",
    "a4b2",
    "a4c2",
    "a4a3",
    "a4b3",
    "a4c3",
    "a4b4",
    "a4c4",
    "a4d4",
    "a4e4",
    "a4f4",
    "a4g4",
    "a4h4",
    "a4a5",
    "a4b5",
    "a4c5",
    "a4a6",
    "a4b6",
    "a4c6",
    "a4a7",
    "a4d7",
    "a4a8",
    "a4e8",
    "b4b1",
    "b4e1",
    "b4a2",
    "b4b2",
    "b4c2",
    "b4d2",
    "b4a3",
    "b4b3",
    "b4c3",
    "b4d3",
    "b4a4",
    "b4c4",
    "b4d4",
    "b4e4",
    "b4f4",
    "b4g4",
    "b4h4",
    "b4a5",
    "b4b5",
    "b4c5",
    "b4d5",
    "b4a6",
    "b4b6",
    "b4c6",
    "b4d6",
    "b4b7",
    "b4e7",
    "b4b8",
    "b4f8",
    "c4c1",
    "c4f1",
    "c4a2",
    "c4b2",
    "c4c2",
    "c4d2",
    "c4e2",
    "c4a3",
    "c4b3",
    "c4c3",
    "c4d3",
    "c4e3",
    "c4a4",
    "c4b4",
    "c4d4",
    "c4e4",
    "c4f4",
    "c4g4",
    "c4h4",
    "c4a5",
    "c4b5",
    "c4c5",
    "c4d5",
    "c4e5",
    "c4a6",
    "c4b6",
    "c4c6",
    "c4d6",
    "c4e6",
    "c4c7",
    "c4f7",
    "c4c8",
    "c4g8",
    "d4a1",
    "d4d1",
    "d4g1",
    "d4b2",
    "d4c2",
    "d4d2",
    "d4e2",
    "d4f2",
    "d4b3",
    "d4c3",
    "d4d3",
    "d4e3",
    "d4f3",
    "d4a4",
    "d4b4",
    "d4c4",
    "d4e4",
    "d4f4",
    "d4g4",
    "d4h4",
    "d4b5",
    "d4c5",
    "d4d5",
    "d4e5",
    "d4f5",
    "d4b6",
    "d4c6",
    "d4d6",
    "d4e6",
    "d4f6",
    "d4a7",
    "d4d7",
    "d4g7",
    "d4d8",
    "d4h8",
    "e4b1",
    "e4e1",
    "e4h1",
    "e4c2",
    "e4d2",
    "e4e2",
    "e4f2",
    "e4g2",
    "e4c3",
    "e4d3",
    "e4e3",
    "e4f3",
    "e4g3",
    "e4a4",
    "e4b4",
    "e4c4",
    "e4d4",
    "e4f4",
    "e4g4",
    "e4h4",
    "e4c5",
    "e4d5",
    "e4e5",
    "e4f5",
    "e4g5",
    "e4c6",
    "e4d6",
    "e4e6",
    "e4f6",
    "e4g6",
    "e4b7",
    "e4e7",
    "e4h7",
    "e4a8",
    "e4e8",
    "f4c1",
    "f4f1",
    "f4d2",
    "f4e2",
    "f4f2",
    "f4g2",
    "f4h2",
    "f4d3",
    "f4e3",
    "f4f3",
    "f4g3",
    "f4h3",
    "f4a4",
    "f4b4",
    "f4c4",
    "f4d4",
    "f4e4",
    "f4g4",
    "f4h4",
    "f4d5",
    "f4e5",
    "f4f5",
    "f4g5",
    "f4h5",
    "f4d6",
    "f4e6",
    "f4f6",
    "f4g6",
    "f4h6",
    "f4c7",
    "f4f7",
    "f4b8",
    "f4f8",
    "g4d1",
    "g4g1",
    "g4e2",
    "g4f2",
    "g4g2",
    "g4h2",
    "g4e3",
    "g4f3",
    "g4g3",
    "g4h3",
    "g4a4",
    "g4b4",
    "g4c4",
    "g4d4",
    "g4e4",
    "g4f4",
    "g4h4",
    "g4e5",
    "g4f5",
    "g4g5",
    "g4h5",
    "g4e6",
    "g4f6",
    "g4g6",
    "g4h6",
    "g4d7",
    "g4g7",
    "g4c8",
    "g4g8",
    "h4e1",
    "h4h1",
    "h4f2",
    "h4g2",
    "h4h2",
    "h4f3",
    "h4g3",
    "h4h3",
    "h4a4",
    "h4b4",
    "h4c4",
    "h4d4",
    "h4e4",
    "h4f4",
    "h4g4",
    "h4f5",
    "h4g5",
    "h4h5",
    "h4f6",
    "h4g6",
    "h4h6",
    "h4e7",
    "h4h7",
    "h4d8",
    "h4h8",
    "a5a1",
    "a5e1",
    "a5a2",
    "a5d2",
    "a5a3",
    "a5b3",
    "a5c3",
    "a5a4",
    "a5b4",
    "a5c4",
    "a5b5",
    "a5c5",
    "a5d5",
    "a5e5",
    "a5f5",
    "a5g5",
    "a5h5",
    "a5a6",
    "a5b6",
    "a5c6",
    "a5a7",
    "a5b7",
    "a5c7",
    "a5a8",
    "a5d8",
    "b5b1",
    "b5f1",
    "b5b2",
    "b5e2",
    "b5a3",
    "b5b3",
    "b5c3",
    "b5d3",
    "b5a4",
    "b5b4",
    "b5c4",
    "b5d4",
    "b5a5",
    "b5c5",
    "b5d5",
    "b5e5",
    "b5f5",
    "b5g5",
    "b5h5",
    "b5a6",
    "b5b6",
    "b5c6",
    "b5d6",
    "b5a7",
    "b5b7",
    "b5c7",
    "b5d7",
    "b5b8",
    "b5e8",
    "c5c1",
    "c5g1",
    "c5c2",
    "c5f2",
    "c5a3",
    "c5b3",
    "c5c3",
    "c5d3",
    "c5e3",
    "c5a4",
    "c5b4",
    "c5c4",
    "c5d4",
    "c5e4",
    "c5a5",
    "c5b5",
    "c5d5",
    "c5e5",
    "c5f5",
    "c5g5",
    "c5h5",
    "c5a6",
    "c5b6",
    "c5c6",
    "c5d6",
    "c5e6",
    "c5a7",
    "c5b7",
    "c5c7",
    "c5d7",
    "c5e7",
    "c5c8",
    "c5f8",
    "d5d1",
    "d5h1",
    "d5a2",
    "d5d2",
    "d5g2",
    "d5b3",
    "d5c3",
    "d5d3",
    "d5e3",
    "d5f3",
    "d5b4",
    "d5c4",
    "d5d4",
    "d5e4",
    "d5f4",
    "d5a5",
    "d5b5",
    "d5c5",
    "d5e5",
    "d5f5",
    "d5g5",
    "d5h5",
    "d5b6",
    "d5c6",
    "d5d6",
    "d5e6",
    "d5f6",
    "d5b7",
    "d5c7",
    "d5d7",
    "d5e7",
    "d5f7",
    "d5a8",
    "d5d8",
    "d5g8",
    "e5a1",
    "e5e1",
    "e5b2",
    "e5e2",
    "e5h2",
    "e5c3",
    "e5d3",
    "e5e3",
    "e5f3",
    "e5g3",
    "e5c4",
    "e5d4",
    "e5e4",
    "e5f4",
    "e5g4",
    "e5a5",
    "e5b5",
    "e5c5",
    "e5d5",
    "e5f5",
    "e5g5",
    "e5h5",
    "e5c6",
    "e5d6",
    "e5e6",
    "e5f6",
    "e5g6",
    "e5c7",
    "e5d7",
    "e5e7",
    "e5f7",
    "e5g7",
    "e5b8",
    "e5e8",
    "e5h8",
    "f5b1",
    "f5f1",
    "f5c2",
    "f5f2",
    "f5d3",
    "f5e3",
    "f5f3",
    "f5g3",
    "f5h3",
    "f5d4",
    "f5e4",
    "f5f4",
    "f5g4",
    "f5h4",
    "f5a5",
    "f5b5",
    "f5c5",
    "f5d5",
    "f5e5",
    "f5g5",
    "f5h5",
    "f5d6",
    "f5e6",
    "f5f6",
    "f5g6",
    "f5h6",
    "f5d7",
    "f5e7",
    "f5f7",
    "f5g7",
    "f5h7",
    "f5c8",
    "f5f8",
    "g5c1",
    "g5g1",
    "g5d2",
    "g5g2",
    "g5e3",
    "g5f3",
    "g5g3",
    "g5h3",
    "g5e4",
    "g5f4",
    "g5g4",
    "g5h4",
    "g5a5",
    "g5b5",
    "g5c5",
    "g5d5",
    "g5e5",
    "g5f5",
    "g5h5",
    "g5e6",
    "g5f6",
    "g5g6",
    "g5h6",
    "g5e7",
    "g5f7",
    "g5g7",
    "g5h7",
    "g5d8",
    "g5g8",
    "h5d1",
    "h5h1",
    "h5e2",
    "h5h2",
    "h5f3",
    "h5g3",
    "h5h3",
    "h5f4",
    "h5g4",
    "h5h4",
    "h5a5",
    "h5b5",
    "h5c5",
    "h5d5",
    "h5e5",
    "h5f5",
    "h5g5",
    "h5f6",
    "h5g6",
    "h5h6",
    "h5f7",
    "h5g7",
    "h5h7",
    "h5e8",
    "h5h8",
    "a6a1",
    "a6f1",
    "a6a2",
    "a6e2",
    "a6a3",
    "a6d3",
    "a6a4",
    "a6b4",
    "a6c4",
    "a6a5",
    "a6b5",
    "a6c5",
    "a6b6",
    "a6c6",
    "a6d6",
    "a6e6",
    "a6f6",
    "a6g6",
    "a6h6",
    "a6a7",
    "a6b7",
    "a6c7",
    "a6a8",
    "a6b8",
    "a6c8",
    "b6b1",
    "b6g1",
    "b6b2",
    "b6f2",
    "b6b3",
    "b6e3",
    "b6a4",
    "b6b4",
    "b6c4",
    "b6d4",
    "b6a5",
    "b6b5",
    "b6c5",
    "b6d5",
    "b6a6",
    "b6c6",
    "b6d6",
    "b6e6",
    "b6f6",
    "b6g6",
    "b6h6",
    "b6a7",
    "b6b7",
    "b6c7",
    "b6d7",
    "b6a8",
    "b6b8",
    "b6c8",
    "b6d8",
    "c6c1",
    "c6h1",
    "c6c2",
    "c6g2",
    "c6c3",
    "c6f3",
    "c6a4",
    "c6b4",
    "c6c4",
    "c6d4",
    "c6e4",
    "c6a5",
    "c6b5",
    "c6c5",
    "c6d5",
    "c6e5",
    "c6a6",
    "c6b6",
    "c6d6",
    "c6e6",
    "c6f6",
    "c6g6",
    "c6h6",
    "c6a7",
    "c6b7",
    "c6c7",
    "c6d7",
    "c6e7",
    "c6a8",
    "c6b8",
    "c6c8",
    "c6d8",
    "c6e8",
    "d6d1",
    "d6d2",
    "d6h2",
    "d6a3",
    "d6d3",
    "d6g3",
    "d6b4",
    "d6c4",
    "d6d4",
    "d6e4",
    "d6f4",
    "d6b5",
    "d6c5",
    "d6d5",
    "d6e5",
    "d6f5",
    "d6a6",
    "d6b6",
    "d6c6",
    "d6e6",
    "d6f6",
    "d6g6",
    "d6h6",
    "d6b7",
    "d6c7",
    "d6d7",
    "d6e7",
    "d6f7",
    "d6b8",
    "d6c8",
    "d6d8",
    "d6e8",
    "d6f8",
    "e6e1",
    "e6a2",
    "e6e2",
    "e6b3",
    "e6e3",
    "e6h3",
    "e6c4",
    "e6d4",
    "e6e4",
    "e6f4",
    "e6g4",
    "e6c5",
    "e6d5",
    "e6e5",
    "e6f5",
    "e6g5",
    "e6a6",
    "e6b6",
    "e6c6",
    "e6d6",
    "e6f6",
    "e6g6",
    "e6h6",
    "e6c7",
    "e6d7",
    "e6e7",
    "e6f7",
    "e6g7",
    "e6c8",
    "e6d8",
    "e6e8",
    "e6f8",
    "e6g8",
    "f6a1",
    "f6f1",
    "f6b2",
    "f6f2",
    "f6c3",
    "f6f3",
    "f6d4",
    "f6e4",
    "f6f4",
    "f6g4",
    "f6h4",
    "f6d5",
    "f6e5",
    "f6f5",
    "f6g5",
    "f6h5",
    "f6a6",
    "f6b6",
    "f6c6",
    "f6d6",
    "f6e6",
    "f6g6",
    "f6h6",
    "f6d7",
    "f6e7",
    "f6f7",
    "f6g7",
    "f6h7",
    "f6d8",
    "f6e8",
    "f6f8",
    "f6g8",
    "f6h8",
    "g6b1",
    "g6g1",
    "g6c2",
    "g6g2",
    "g6d3",
    "g6g3",
    "g6e4",
    "g6f4",
    "g6g4",
    "g6h4",
    "g6e5",
    "g6f5",
    "g6g5",
    "g6h5",
    "g6a6",
    "g6b6",
    "g6c6",
    "g6d6",
    "g6e6",
    "g6f6",
    "g6h6",
    "g6e7",
    "g6f7",
    "g6g7",
    "g6h7",
    "g6e8",
    "g6f8",
    "g6g8",
    "g6h8",
    "h6c1",
    "h6h1",
    "h6d2",
    "h6h2",
    "h6e3",
    "h6h3",
    "h6f4",
    "h6g4",
    "h6h4",
    "h6f5",
    "h6g5",
    "h6h5",
    "h6a6",
    "h6b6",
    "h6c6",
    "h6d6",
    "h6e6",
    "h6f6",
    "h6g6",
    "h6f7",
    "h6g7",
    "h6h7",
    "h6f8",
    "h6g8",
    "h6h8",
    "a7a1",
    "a7g1",
    "a7a2",
    "a7f2",
    "a7a3",
    "a7e3",
    "a7a4",
    "a7d4",
    "a7a5",
    "a7b5",
    "a7c5",
    "a7a6",
    "a7b6",
    "a7c6",
    "a7b7",
    "a7c7",
    "a7d7",
    "a7e7",
    "a7f7",
    "a7g7",
    "a7h7",
    "a7a8",
    "a7b8",
    "a7c8",
    "b7b1",
    "b7h1",
    "b7b2",
    "b7g2",
    "b7b3",
    "b7f3",
    "b7b4",
    "b7e4",
    "b7a5",
    "b7b5",
    "b7c5",
    "b7d5",
    "b7a6",
    "b7b6",
    "b7c6",
    "b7d6",
    "b7a7",
    "b7c7",
    "b7d7",
    "b7e7",
    "b7f7",
    "b7g7",
    "b7h7",
    "b7a8",
    "b7b8",
    "b7c8",
    "b7d8",
    "c7c1",
    "c7c2",
    "c7h2",
    "c7c3",
    "c7g3",
    "c7c4",
    "c7f4",
    "c7a5",
    "c7b5",
    "c7c5",
    "c7d5",
    "c7e5",
    "c7a6",
    "c7b6",
    "c7c6",
    "c7d6",
    "c7e6",
    "c7a7",
    "c7b7",
    "c7d7",
    "c7e7",
    "c7f7",
    "c7g7",
    "c7h7",
    "c7a8",
    "c7b8",
    "c7c8",
    "c7d8",
    "c7e8",
    "d7d1",
    "d7d2",
    "d7d3",
    "d7h3",
    "d7a4",
    "d7d4",
    "d7g4",
    "d7b5",
    "d7c5",
    "d7d5",
    "d7e5",
    "d7f5",
    "d7b6",
    "d7c6",
    "d7d6",
    "d7e6",
    "d7f6",
    "d7a7",
    "d7b7",
    "d7c7",
    "d7e7",
    "d7f7",
    "d7g7",
    "d7h7",
    "d7b8",
    "d7c8",
    "d7d8",
    "d7e8",
    "d7f8",
    "e7e1",
    "e7e2",
    "e7a3",
    "e7e3",
    "e7b4",
    "e7e4",
    "e7h4",
    "e7c5",
    "e7d5",
    "e7e5",
    "e7f5",
    "e7g5",
    "e7c6",
    "e7d6",
    "e7e6",
    "e7f6",
    "e7g6",
    "e7a7",
    "e7b7",
    "e7c7",
    "e7d7",
    "e7f7",
    "e7g7",
    "e7h7",
    "e7c8",
    "e7d8",
    "e7e8",
    "e7f8",
    "e7g8",
    "f7f1",
    "f7a2",
    "f7f2",
    "f7b3",
    "f7f3",
    "f7c4",
    "f7f4",
    "f7d5",
    "f7e5",
    "f7f5",
    "f7g5",
    "f7h5",
    "f7d6",
    "f7e6",
    "f7f6",
    "f7g6",
    "f7h6",
    "f7a7",
    "f7b7",
    "f7c7",
    "f7d7",
    "f7e7",
    "f7g7",
    "f7h7",
    "f7d8",
    "f7e8",
    "f7f8",
    "f7g8",
    "f7h8",
    "g7a1",
    "g7g1",
    "g7b2",
    "g7g2",
    "g7c3",
    "g7g3",
    "g7d4",
    "g7g4",
    "g7e5",
    "g7f5",
    "g7g5",
    "g7h5",
    "g7e6",
    "g7f6",
    "g7g6",
    "g7h6",
    "g7a7",
    "g7b7",
    "g7c7",
    "g7d7",
    "g7e7",
    "g7f7",
    "g7h7",
    "g7e8",
    "g7f8",
    "g7g8",
    "g7h8",
    "h7b1",
    "h7h1",
    "h7c2",
    "h7h2",
    "h7d3",
    "h7h3",
    "h7e4",
    "h7h4",
    "h7f5",
    "h7g5",
    "h7h5",
    "h7f6",
    "h7g6",
    "h7h6",
    "h7a7",
    "h7b7",
    "h7c7",
    "h7d7",
    "h7e7",
    "h7f7",
    "h7g7",
    "h7f8",
    "h7g8",
    "h7h8",
    "a8a1",
    "a8h1",
    "a8a2",
    "a8g2",
    "a8a3",
    "a8f3",
    "a8a4",
    "a8e4",
    "a8a5",
    "a8d5",
    "a8a6",
    "a8b6",
    "a8c6",
    "a8a7",
    "a8b7",
    "a8c7",
    "a8b8",
    "a8c8",
    "a8d8",
    "a8e8",
    "a8f8",
    "a8g8",
    "a8h8",
    "b8b1",
    "b8b2",
    "b8h2",
    "b8b3",
    "b8g3",
    "b8b4",
    "b8f4",
    "b8b5",
    "b8e5",
    "b8a6",
    "b8b6",
    "b8c6",
    "b8d6",
    "b8a7",
    "b8b7",
    "b8c7",
    "b8d7",
    "b8a8",
    "b8c8",
    "b8d8",
    "b8e8",
    "b8f8",
    "b8g8",
    "b8h8",
    "c8c1",
    "c8c2",
    "c8c3",
    "c8h3",
    "c8c4",
    "c8g4",
    "c8c5",
    "c8f5",
    "c8a6",
    "c8b6",
    "c8c6",
    "c8d6",
    "c8e6",
    "c8a7",
    "c8b7",
    "c8c7",
    "c8d7",
    "c8e7",
    "c8a8",
    "c8b8",
    "c8d8",
    "c8e8",
    "c8f8",
    "c8g8",
    "c8h8",
    "d8d1",
    "d8d2",
    "d8d3",
    "d8d4",
    "d8h4",
    "d8a5",
    "d8d5",
    "d8g5",
    "d8b6",
    "d8c6",
    "d8d6",
    "d8e6",
    "d8f6",
    "d8b7",
    "d8c7",
    "d8d7",
    "d8e7",
    "d8f7",
    "d8a8",
    "d8b8",
    "d8c8",
    "d8e8",
    "d8f8",
    "d8g8",
    "d8h8",
    "e8e1",
    "e8e2",
    "e8e3",
    "e8a4",
    "e8e4",
    "e8b5",
    "e8e5",
    "e8h5",
    "e8c6",
    "e8d6",
    "e8e6",
    "e8f6",
    "e8g6",
    "e8c7",
    "e8d7",
    "e8e7",
    "e8f7",
    "e8g7",
    "e8a8",
    "e8b8",
    "e8c8",
    "e8d8",
    "e8f8",
    "e8g8",
    "e8h8",
    "f8f1",
    "f8f2",
    "f8a3",
    "f8f3",
    "f8b4",
    "f8f4",
    "f8c5",
    "f8f5",
    "f8d6",
    "f8e6",
    "f8f6",
    "f8g6",
    "f8h6",
    "f8d7",
    "f8e7",
    "f8f7",
    "f8g7",
    "f8h7",
    "f8a8",
    "f8b8",
    "f8c8",
    "f8d8",
    "f8e8",
    "f8g8",
    "f8h8",
    "g8g1",
    "g8a2",
    "g8g2",
    "g8b3",
    "g8g3",
    "g8c4",
    "g8g4",
    "g8d5",
    "g8g5",
    "g8e6",
    "g8f6",
    "g8g6",
    "g8h6",
    "g8e7",
    "g8f7",
    "g8g7",
    "g8h7",
    "g8a8",
    "g8b8",
    "g8c8",
    "g8d8",
    "g8e8",
    "g8f8",
    "g8h8",
    "h8a1",
    "h8h1",
    "h8b2",
    "h8h2",
    "h8c3",
    "h8h3",
    "h8d4",
    "h8h4",
    "h8e5",
    "h8h5",
    "h8f6",
    "h8g6",
    "h8h6",
    "h8f7",
    "h8g7",
    "h8h7",
    "h8a8",
    "h8b8",
    "h8c8",
    "h8d8",
    "h8e8",
    "h8f8",
    "h8g8",
    "a7a8q",
    "a7a8r",
    "a7a8b",
    "a7b8q",
    "a7b8r",
    "a7b8b",
    "b7a8q",
    "b7a8r",
    "b7a8b",
    "b7b8q",
    "b7b8r",
    "b7b8b",
    "b7c8q",
    "b7c8r",
    "b7c8b",
    "c7b8q",
    "c7b8r",
    "c7b8b",
    "c7c8q",
    "c7c8r",
    "c7c8b",
    "c7d8q",
    "c7d8r",
    "c7d8b",
    "d7c8q",
    "d7c8r",
    "d7c8b",
    "d7d8q",
    "d7d8r",
    "d7d8b",
    "d7e8q",
    "d7e8r",
    "d7e8b",
    "e7d8q",
    "e7d8r",
    "e7d8b",
    "e7e8q",
    "e7e8r",
    "e7e8b",
    "e7f8q",
    "e7f8r",
    "e7f8b",
    "f7e8q",
    "f7e8r",
    "f7e8b",
    "f7f8q",
    "f7f8r",
    "f7f8b",
    "f7g8q",
    "f7g8r",
    "f7g8b",
    "g7f8q",
    "g7f8r",
    "g7f8b",
    "g7g8q",
    "g7g8r",
    "g7g8b",
    "g7h8q",
    "g7h8r",
    "g7h8b",
    "h7g8q",
    "h7g8r",
    "h7g8b",
    "h7h8q",
    "h7h8r",
    "h7h8b"
  ];
  var POLICY_INDEX_MAP = new Map(
    POLICY_INDEX.map((move, index) => [move, index])
  );

  // brain/maia/encoding.ts
  var TOTAL_PLANES = 112;
  var HISTORY_LENGTH = 8;
  var PLANES_PER_HISTORY = 13;
  var PLANE_SIZE = 64;
  var RANKS = "12345678";
  var PIECE_PLANES_WHITE = {
    P: 0,
    N: 1,
    B: 2,
    R: 3,
    Q: 4,
    K: 5,
    p: 6,
    n: 7,
    b: 8,
    r: 9,
    q: 10,
    k: 11
  };
  var PIECE_PLANES_BLACK = {
    p: 0,
    n: 1,
    b: 2,
    r: 3,
    q: 4,
    k: 5,
    P: 6,
    N: 7,
    B: 8,
    R: 9,
    Q: 10,
    K: 11
  };
  function flipRank(square) {
    const file2 = square[0];
    const rankIndex = RANKS.indexOf(square[1]);
    if (rankIndex < 0) return square;
    return `${file2}${RANKS[7 - rankIndex]}`;
  }
  function flipUci(uci) {
    if (uci.length < 4) return uci;
    const from = flipRank(uci.slice(0, 2));
    const to = flipRank(uci.slice(2, 4));
    const promo = uci.length > 4 ? uci.slice(4) : "";
    return `${from}${to}${promo}`;
  }
  function writeConstantPlane(planes, planeIndex, value) {
    const offset = planeIndex * PLANE_SIZE;
    for (let i = 0; i < PLANE_SIZE; i++) {
      planes[offset + i] = value;
    }
  }
  var normalizeFenKey = (fen) => fen.split(" ").slice(0, 4).join(" ");
  function buildRepetitionFlags(fenHistory) {
    const counts = /* @__PURE__ */ new Map();
    return fenHistory.map((fen) => {
      const key = normalizeFenKey(fen);
      const current = counts.get(key) ?? 0;
      counts.set(key, current + 1);
      return current > 0;
    });
  }
  function encodeFenHistory(fenHistory) {
    if (fenHistory.length === 0) {
      throw new Error("fenHistory must include at least the current position");
    }
    const currentFen = fenHistory[fenHistory.length - 1];
    const fenParts = currentFen.split(" ");
    const sideToMove = fenParts[1] ?? "w";
    const castling = fenParts[2] ?? "-";
    const halfmoveClock = Number(fenParts[4] ?? "0");
    const isBlack = sideToMove === "b";
    const piecePlanes = isBlack ? PIECE_PLANES_BLACK : PIECE_PLANES_WHITE;
    const repetitionFlags = buildRepetitionFlags(fenHistory);
    const planes = new Float32Array(TOTAL_PLANES * PLANE_SIZE);
    const recentPositions = fenHistory.slice(-HISTORY_LENGTH).reverse();
    const recentRepetitions = repetitionFlags.slice(-HISTORY_LENGTH).reverse();
    for (let historyIndex = 0; historyIndex < HISTORY_LENGTH; historyIndex++) {
      const fen = recentPositions[historyIndex];
      if (!fen) continue;
      const [boardPart] = fen.split(" ");
      const ranks = boardPart.split("/");
      const basePlane = historyIndex * PLANES_PER_HISTORY;
      let rank2 = 7;
      for (const rankStr of ranks) {
        let file2 = 0;
        for (const ch of rankStr) {
          if (ch >= "1" && ch <= "8") {
            file2 += Number(ch);
          } else {
            const planeIndex = piecePlanes[ch];
            if (planeIndex !== void 0) {
              const actualRank = isBlack ? 7 - rank2 : rank2;
              const squareIndex = actualRank * 8 + file2;
              planes[(basePlane + planeIndex) * PLANE_SIZE + squareIndex] = 1;
            }
            file2 += 1;
          }
        }
        rank2 -= 1;
      }
      if (recentRepetitions[historyIndex]) {
        writeConstantPlane(planes, basePlane + 12, 1);
      }
    }
    if (isBlack) {
      writeConstantPlane(planes, 104, castling.includes("q") ? 1 : 0);
      writeConstantPlane(planes, 105, castling.includes("k") ? 1 : 0);
      writeConstantPlane(planes, 106, castling.includes("Q") ? 1 : 0);
      writeConstantPlane(planes, 107, castling.includes("K") ? 1 : 0);
    } else {
      writeConstantPlane(planes, 104, castling.includes("Q") ? 1 : 0);
      writeConstantPlane(planes, 105, castling.includes("K") ? 1 : 0);
      writeConstantPlane(planes, 106, castling.includes("q") ? 1 : 0);
      writeConstantPlane(planes, 107, castling.includes("k") ? 1 : 0);
    }
    writeConstantPlane(planes, 108, isBlack ? 1 : 0);
    writeConstantPlane(planes, 109, Math.min(halfmoveClock / 99, 1));
    writeConstantPlane(planes, 110, 0);
    writeConstantPlane(planes, 111, 1);
    return planes;
  }

  // brain/maia/decoding.ts
  function decodePolicyOutput(policyLogits, legalMoves, isBlack, temperature = 0) {
    if (legalMoves.length === 0) {
      throw new Error("No legal moves to decode");
    }
    const moveLogits = [];
    for (const uci of legalMoves) {
      const canonicalMove = isBlack ? flipUci(uci) : uci;
      let index = POLICY_INDEX_MAP.get(canonicalMove);
      if (index === void 0 && canonicalMove.endsWith("n")) {
        index = POLICY_INDEX_MAP.get(canonicalMove.slice(0, 4));
      }
      if (index === void 0) {
        console.warn(`No policy index found for move: ${uci} (canonical: ${canonicalMove})`);
        continue;
      }
      moveLogits.push({ move: uci, logit: policyLogits[index] });
    }
    if (moveLogits.length === 0) {
      throw new Error("No legal moves could be mapped to policy indices");
    }
    const maxLogit = Math.max(...moveLogits.map((m) => m.logit));
    const temp = temperature > 0 ? temperature : 1;
    const exps = moveLogits.map((m) => Math.exp((m.logit - maxLogit) / temp));
    const sumExp = exps.reduce((a, b) => a + b, 0);
    const probs = exps.map((e) => e / sumExp);
    const scoredMoves = moveLogits.map((m, i) => ({
      move: m.move,
      confidence: probs[i]
    }));
    scoredMoves.sort((a, b) => b.confidence - a.confidence);
    let selected;
    if (temperature > 0) {
      const rand2 = Math.random();
      let cumulative = 0;
      selected = scoredMoves[scoredMoves.length - 1];
      for (const move of scoredMoves) {
        cumulative += move.confidence;
        if (rand2 <= cumulative) {
          selected = move;
          break;
        }
      }
    } else {
      selected = scoredMoves[0];
    }
    return {
      best: selected,
      topMoves: scoredMoves.slice(0, 5)
    };
  }

  // flutter/native_src/maia-brain.ts
  var MAIA_BRAIN_VERSION = 1;
  var legalUcis = (fen) => new Chess(fen).moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ""));
  function maiaPlanes(fenHistory) {
    const fen = fenHistory[fenHistory.length - 1];
    if (!fen) return null;
    if (legalUcis(fen).length === 0) return null;
    return Array.from(encodeFenHistory(fenHistory));
  }
  function maiaPick(policy, fen, temperature) {
    const legal = legalUcis(fen);
    if (legal.length === 0) return null;
    const isBlack = fen.split(" ")[1] === "b";
    return decodePolicyOutput(new Float32Array(policy), legal, isBlack, temperature).best.move;
  }
  return __toCommonJS(maia_brain_exports);
})();
/*! Bundled license information:

chess.js/dist/esm/chess.js:
  (**
   * @license
   * Copyright (c) 2025, Jeff Hlywa (jhlywa@gmail.com)
   * All rights reserved.
   *
   * Redistribution and use in source and binary forms, with or without
   * modification, are permitted provided that the following conditions are met:
   *
   * 1. Redistributions of source code must retain the above copyright notice,
   *    this list of conditions and the following disclaimer.
   * 2. Redistributions in binary form must reproduce the above copyright notice,
   *    this list of conditions and the following disclaimer in the documentation
   *    and/or other materials provided with the distribution.
   *
   * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
   * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
   * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
   * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
   * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
   * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
   * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
   * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
   * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
   * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
   * POSSIBILITY OF SUCH DAMAGE.
   *)
*/
