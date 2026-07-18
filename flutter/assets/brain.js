"use strict";
var brain = (() => {
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

  // brain/brain-entry.ts
  var brain_entry_exports = {};
  __export(brain_entry_exports, {
    BOT_MODEL: () => BOT_MODEL,
    BRAIN_VERSION: () => BRAIN_VERSION,
    CLASS: () => CLASS,
    LABEL_ORDER: () => LABEL_ORDER,
    LABEL_VERSION: () => LABEL_VERSION,
    MOTIF_TAGS_VERSION: () => MOTIF_TAGS_VERSION,
    PERSONAS: () => PERSONAS,
    SCALE_OFFSET: () => SCALE_OFFSET,
    addItem: () => addItem,
    availablePersonas: () => availablePersonas,
    avoidRepetition: () => avoidRepetition,
    backfillGrade: () => backfillGrade,
    bestMovePoint: () => bestMovePoint,
    botDelay: () => botDelay,
    botEloMax: () => botEloMax,
    botEloMin: () => botEloMin,
    botRecipe: () => botRecipe,
    botSpec: () => botSpec,
    controlSquares: () => controlSquares,
    dueCount: () => dueCount,
    enPassantSetup: () => enPassantSetup,
    estimatePlayerElo: () => estimatePlayerElo,
    explainGoodMove: () => explainGoodMove,
    explainMove: () => explainMove,
    gameAccuracy: () => gameAccuracy,
    getBotSubstrate: () => getBotSubstrate,
    getFenAfter: () => getFenAfter,
    getNumberedSanLine: () => getNumberedSanLine,
    getSan: () => getSan,
    getSanLine: () => getSanLine,
    gradeMove: () => gradeMove,
    isCapture: () => isCapture,
    itemDataFromStoredMove: () => itemDataFromStoredMove,
    judgeThreat: () => judgeThreat,
    labelCounts: () => labelCounts,
    masteryStats: () => masteryStats,
    motifTags: () => motifTags,
    moveAccuracy: () => moveAccuracy,
    nextItem: () => nextItem,
    parseSpec: () => parseSpec,
    personaById: () => personaById,
    personaInternalElo: () => personaInternalElo,
    puzzleDifficulty: () => puzzleDifficulty,
    puzzleSetupMove: () => puzzleSetupMove,
    recordResult: () => recordResult,
    removeItem: () => removeItem,
    samplerAlphaFor: () => samplerAlphaFor,
    selectBotMove: () => selectBotMove,
    setBotSubstrate: () => setBotSubstrate,
    shapedBotMove: () => shapedBotMove,
    shapedLabelFor: () => shapedLabelFor,
    shapedParams: () => shapedParams,
    shapedSearchDepth: () => shapedSearchDepth,
    shapedStrengthRange: () => shapedStrengthRange,
    specToRecipe: () => specToRecipe,
    threatProbeFen: () => threatProbeFen,
    whitePovWinChance: () => whitePovWinChance,
    winChance: () => winChance
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
  function pgn(headers, game2) {
    if (game2.marker && game2.marker.comment) {
      let node2 = game2.root;
      while (true) {
        const next = node2.variations[0];
        if (!next) {
          node2.comment = game2.marker.comment;
          break;
        }
        node2 = next;
      }
    }
    return {
      headers,
      root: game2.root,
      result: (game2.marker && game2.marker.result) ?? void 0
    };
  }
  function peg$subclass(child, parent) {
    function C() {
      this.constructor = child;
    }
    C.prototype = parent.prototype;
    child.prototype = new C();
  }
  function peg$SyntaxError(message, expected2, found, location) {
    var self = Error.call(this, message);
    if (Object.setPrototypeOf) {
      Object.setPrototypeOf(self, peg$SyntaxError.prototype);
    }
    self.expected = expected2;
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
  peg$SyntaxError.buildMessage = function(expected2, found) {
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
    function describeExpected(expected3) {
      var descriptions = expected3.map(describeExpectation);
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
    return "Expected " + describeExpected(expected2) + " but " + describeFound(found) + " found.";
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
    var peg$f0 = function(headers, game2) {
      return pgn(headers, game2);
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
    function peg$fail(expected2) {
      if (peg$currPos < peg$maxFailPos) {
        return;
      }
      if (peg$currPos > peg$maxFailPos) {
        peg$maxFailPos = peg$currPos;
        peg$maxFailExpected = [];
      }
      peg$maxFailExpected.push(expected2);
    }
    function peg$buildStructuredError(expected2, found, location) {
      return new peg$SyntaxError(
        peg$SyntaxError.buildMessage(expected2, found),
        expected2,
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
  function rank(square2) {
    return square2 >> 4;
  }
  function file(square2) {
    return square2 & 15;
  }
  function isDigit(c) {
    return "0123456789".indexOf(c) !== -1;
  }
  function algebraic(square2) {
    const f = file(square2);
    const r = rank(square2);
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
      let square2 = 0;
      this.clear({ preserveHeaders });
      for (let i = 0; i < position.length; i++) {
        const piece = position.charAt(i);
        if (piece === "/") {
          square2 += 8;
        } else if (isDigit(piece)) {
          square2 += parseInt(piece, 10);
        } else {
          const color = piece < "a" ? WHITE : BLACK;
          this._put({ type: piece.toLowerCase(), color }, algebraic(square2));
          square2++;
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
          for (const square2 of squares) {
            if (square2 & 136) {
              continue;
            }
            const color = this._turn;
            if (this._board[square2]?.color === color && this._board[square2]?.type === PAWN) {
              this._makeMove({
                color,
                from: square2,
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
    get(square2) {
      return this._board[Ox88[square2]];
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
    put({ type, color }, square2) {
      if (this._put({ type, color }, square2)) {
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
    _put({ type, color }, square2) {
      if (SYMBOLS.indexOf(type.toLowerCase()) === -1) {
        return false;
      }
      if (!(square2 in Ox88)) {
        return false;
      }
      const sq = Ox88[square2];
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
    remove(square2) {
      const piece = this.get(square2);
      this._clear(Ox88[square2]);
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
      const canCapture = (square2) => !(square2 & 136) && this._board[square2]?.color === this._turn && this._board[square2]?.type === PAWN;
      if (!attackers.some(canCapture)) {
        this._hash ^= this._epKey();
        this._epSquare = EMPTY;
      }
    }
    _attacked(color, square2, verbose) {
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
        const difference = i - square2;
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
          while (j !== square2) {
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
    attackers(square2, attackedBy) {
      if (!attackedBy) {
        return this._attacked(this._turn, Ox88[square2], true);
      } else {
        return this._attacked(attackedBy, Ox88[square2], true);
      }
    }
    _isKingAttacked(color) {
      const square2 = this._kings[color];
      return square2 === -1 ? false : this._attacked(swapColor(color), square2);
    }
    hash() {
      return this._hash.toString(16);
    }
    isAttacked(square2, attackedBy) {
      return this._attacked(attackedBy, Ox88[square2]);
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
    moves({ verbose = false, square: square2 = void 0, piece = void 0 } = {}) {
      const moves = this._moves({ square: square2, piece });
      if (verbose) {
        return moves.map((move) => new Move(this, move));
      } else {
        return moves.map((move) => this._moveToSan(move, moves));
      }
    }
    _moves({ legal = true, piece = void 0, square: square2 = void 0 } = {}) {
      const forSquare = square2 ? square2.toLowerCase() : void 0;
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
          const square2 = algebraic(moves[i].from);
          if ((!piece || piece.toLowerCase() == moves[i].piece) && Ox88[to] == moves[i].to && (from == square2[0] || from == square2[1]) && (!promotion || promotion.toLowerCase() == moves[i].promotion)) {
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
    squareColor(square2) {
      if (square2 in Ox88) {
        const sq = Ox88[square2];
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

  // brain/engine/chess.ts
  var game = new Chess();
  function getSanLine(fen, ucis) {
    const steps = [];
    try {
      const tmp = new Chess(fen);
      for (const uci of ucis) {
        const move = tmp.move({
          from: uci.slice(0, 2),
          to: uci.slice(2, 4),
          promotion: uci.length > 4 ? uci[4] : void 0
        });
        if (!move) break;
        steps.push({ san: move.san, uci, color: move.color, piece: move.piece });
      }
    } catch {
    }
    return steps;
  }
  function isCapture(fen, uci) {
    try {
      const move = new Chess(fen).move({
        from: uci.slice(0, 2),
        to: uci.slice(2, 4),
        promotion: uci.length > 4 ? uci[4] : void 0
      });
      return move.captured !== void 0;
    } catch {
      return false;
    }
  }
  function getFenAfter(fen, uci) {
    try {
      const tmp = new Chess(fen);
      tmp.move({
        from: uci.slice(0, 2),
        to: uci.slice(2, 4),
        promotion: uci.length > 4 ? uci[4] : void 0
      });
      return tmp.fen();
    } catch {
      return null;
    }
  }
  function getNumberedSanLine(fen, ucis, max = 12) {
    const parts = [];
    try {
      const tmp = new Chess(fen);
      for (const uci of ucis.slice(0, max)) {
        const num = Number(tmp.fen().split(" ")[5]);
        const move = tmp.move({
          from: uci.slice(0, 2),
          to: uci.slice(2, 4),
          promotion: uci.length > 4 ? uci[4] : void 0
        });
        if (!move) break;
        if (move.color === "w") parts.push(`${num}.${move.san}`);
        else if (parts.length === 0) parts.push(`${num}...${move.san}`);
        else parts.push(move.san);
      }
    } catch {
    }
    return parts.join(" ");
  }
  function getSan(fen, uci) {
    try {
      const tmp = new Chess(fen);
      const from = uci.slice(0, 2);
      const to = uci.slice(2, 4);
      const promotion = uci.length > 4 ? uci[4] : void 0;
      const move = tmp.move({ from, to, promotion });
      return move?.san || uci;
    } catch {
      return uci;
    }
  }

  // brain/engine/explain.ts
  var PIECE_VAL = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
  var VAL = PIECE_VAL;
  var NAME = {
    p: "pawn",
    n: "knight",
    b: "bishop",
    r: "rook",
    q: "queen",
    k: "king"
  };
  function apply(chess, uci) {
    try {
      return chess.move({
        from: uci.slice(0, 2),
        to: uci.slice(2, 4),
        promotion: uci.length > 4 ? uci[4] : void 0
      });
    } catch {
      return null;
    }
  }
  function sanLine(fen, ucis, max = 6) {
    return getSanLine(fen, ucis.slice(0, max)).map((s) => s.san).join(" ");
  }
  function materialOverLine(fen, ucis) {
    const c = new Chess(fen);
    const mover = c.turn();
    let net = 0;
    for (const uci of ucis) {
      const m = apply(c, uci);
      if (!m) break;
      if (m.captured) net += (m.color === mover ? 1 : -1) * VAL[m.captured];
      if (m.promotion) net += (m.color === mover ? 1 : -1) * (VAL[m.promotion] - 1);
    }
    return net;
  }
  function summarizeLine(fen, ucis) {
    const c = new Chess(fen);
    const mover = c.turn();
    const events = [];
    let ply = 0;
    let lastSan = "";
    for (const uci of ucis) {
      const m = apply(c, uci);
      if (!m) break;
      ply++;
      lastSan = m.san;
      if (m.captured) {
        events.push({ ply, square: m.to, victim: m.captured, byMover: m.color === mover, san: m.san });
      }
    }
    if (ply === 0) return void 0;
    const mate = lastSan.endsWith("#");
    const mateByMover = mate && ply % 2 === 1;
    let groups = [];
    for (const e of events) {
      const g = groups[groups.length - 1];
      if (g && e.ply === g[g.length - 1].ply + 1 && e.square === g[g.length - 1].square) g.push(e);
      else groups.push([e]);
    }
    groups = groups.filter(
      (g) => g[g.length - 1].ply !== ply || g.length === 2 && g[0].victim === g[1].victim
    );
    const phrases = [];
    for (const g of groups) {
      if (g.length === 1) {
        const e = g[0];
        phrases.push(
          e.byMover ? `you pick up a ${NAME[e.victim]} (${e.san})` : `your ${NAME[e.victim]} is taken (${e.san})`
        );
      } else if (g.length === 2 && g[0].victim === g[1].victim) {
        phrases.push(`${NAME[g[0].victim]}s are traded on ${g[0].square}`);
      } else if (g.length === 2) {
        const won = g[0].byMover ? g[0].victim : g[1].victim;
        const lost = g[0].byMover ? g[1].victim : g[0].victim;
        if (VAL[won] > VAL[lost]) {
          phrases.push(`you win a ${NAME[won]} for a ${NAME[lost]} on ${g[0].square}`);
        } else if (VAL[won] < VAL[lost]) {
          phrases.push(`you give up a ${NAME[lost]} for a ${NAME[won]} on ${g[0].square}`);
        } else {
          phrases.push(`a ${NAME[won]} and a ${NAME[lost]} are traded on ${g[0].square}`);
        }
      } else {
        const net = g.reduce((a, e) => a + (e.byMover ? VAL[e.victim] : -VAL[e.victim]), 0);
        if (net > 0.5) phrases.push(`you come out ahead in the exchange on ${g[0].square}`);
        else if (net < -0.5) phrases.push(`you come out behind in the exchange on ${g[0].square}`);
        else phrases.push(`pieces are traded on ${g[0].square}`);
      }
    }
    if (phrases.length === 0 && !mate) return void 0;
    let story = phrases.slice(0, 3).join(", then ");
    if (mate) {
      const mateClause = mateByMover ? "mate follows" : "you get mated";
      story = story ? `${story}, and ${mateClause}` : mateClause;
    }
    return story;
  }
  function quietMaterialOverLine(fen, ucis) {
    const c = new Chess(fen);
    const mover = c.turn();
    let net = 0;
    let plies = 0;
    let pawnsOnly = true;
    let quiet = { net: 0, plies: 0, pawnsOnly: true };
    for (const uci of ucis) {
      const m = apply(c, uci);
      if (!m) break;
      plies++;
      if (m.captured) net += (m.color === mover ? 1 : -1) * VAL[m.captured];
      if (m.captured && m.captured !== "p") pawnsOnly = false;
      if (m.promotion) {
        net += (m.color === mover ? 1 : -1) * (VAL[m.promotion] - 1);
        pawnsOnly = false;
      }
      if (!m.captured && !m.promotion) quiet = { net, plies, pawnsOnly };
    }
    return quiet;
  }
  function hangingIssue(fenBefore, playedUci, refutationUci) {
    if (!refutationUci) return void 0;
    const c = new Chess(fenBefore);
    const played = apply(c, playedUci);
    if (!played) return void 0;
    const target = refutationUci.slice(2, 4);
    const victim = c.get(target);
    if (!victim || victim.color !== played.color || victim.type === "p" || victim.type === "k")
      return void 0;
    const defenders = c.attackers(target, played.color).length;
    if (defenders > 0) return void 0;
    const ref = apply(c, refutationUci);
    if (!ref || !ref.captured) return void 0;
    return `This leaves the ${NAME[victim.type]} on ${target} undefended \u2014 ${ref.san} just takes it.`;
  }
  function forkPoint(fenBefore, uci) {
    const c = new Chess(fenBefore);
    const m = apply(c, uci);
    if (!m || m.piece === "k") return void 0;
    if (c.isCheckmate()) return void 0;
    const to = m.to;
    const them = m.color === "w" ? "b" : "w";
    const hunters = c.attackers(to, them).map((sq) => c.get(sq)?.type ?? "k");
    if (hunters.some((t) => t !== "k" && VAL[t] < VAL[m.piece])) return void 0;
    if (hunters.length > 0 && c.attackers(to, m.color).length === 0) return void 0;
    const targets = [];
    for (const row of c.board()) {
      for (const cell of row) {
        if (!cell || cell.color === m.color || cell.type === "p") continue;
        if (!c.attackers(cell.square, m.color).includes(to)) continue;
        const undefended = c.attackers(cell.square, cell.color).length === 0;
        if (cell.type === "k" || VAL[cell.type] > VAL[m.piece] || undefended) {
          targets.push(`${NAME[cell.type]} on ${cell.square}`);
        }
      }
    }
    if (targets.length < 2) return void 0;
    return `${m.san} forks the ${targets.join(" and the ")}.`;
  }
  var BISHOP_DIRS = [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1]
  ];
  var ROOK_DIRS = [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1]
  ];
  function sliderDirs(type) {
    if (type === "b") return BISHOP_DIRS;
    if (type === "r") return ROOK_DIRS;
    if (type === "q") return [...BISHOP_DIRS, ...ROOK_DIRS];
    return null;
  }
  function toSquare(file2, rank2) {
    if (file2 < 0 || file2 > 7 || rank2 < 0 || rank2 > 7) return null;
    return String.fromCharCode(97 + file2) + (rank2 + 1);
  }
  function* raySquares(from, dir) {
    let file2 = from.charCodeAt(0) - 97;
    let rank2 = Number(from[1]) - 1;
    for (; ; ) {
      file2 += dir[0];
      rank2 += dir[1];
      const s = toSquare(file2, rank2);
      if (!s) return;
      yield s;
    }
  }
  function pinOrSkewerPoint(fenBefore, uci) {
    const c = new Chess(fenBefore);
    const m = apply(c, uci);
    if (!m) return void 0;
    if (c.isCheckmate()) return void 0;
    const dirs = sliderDirs(m.piece);
    if (!dirs) return void 0;
    for (const dir of dirs) {
      let first = null;
      for (const s of raySquares(m.to, dir)) {
        const p = c.get(s);
        if (!p) continue;
        if (p.color === m.color) break;
        if (!first) {
          first = { sq: s, type: p.type };
          continue;
        }
        if (c.attackers(m.to, p.color).includes(first.sq)) {
          const probe = new Chess(c.fen());
          let takes = null;
          try {
            takes = probe.move({ from: first.sq, to: m.to, promotion: "q" });
          } catch {
            takes = null;
          }
          if (takes) {
            const recaptured = probe.moves({ verbose: true }).some((r) => r.to === m.to && r.captured);
            if (!recaptured || VAL[m.piece] >= VAL[first.type]) break;
          }
        }
        const wins = VAL[p.type] > VAL[m.piece] || c.attackers(s, p.color).length === 0;
        if (first.type === "k") {
          if (VAL[p.type] >= 3 && wins) {
            return `${m.san} skewers the king on ${first.sq} against the ${NAME[p.type]} on ${s}.`;
          }
        } else if (p.type === "k") {
          return `${m.san} pins the ${NAME[first.type]} on ${first.sq} against the king.`;
        } else if (VAL[p.type] > VAL[first.type]) {
          const pawnOnFile = first.type === "p" && dir[0] === 0;
          if (wins && !pawnOnFile) {
            return `${m.san} pins the ${NAME[first.type]} on ${first.sq} against the ${NAME[p.type]} on ${s}.`;
          }
        } else if (first.type === "q" && VAL[m.piece] < 9 && VAL[p.type] >= 3 && wins) {
          return `${m.san} skewers the queen on ${first.sq} against the ${NAME[p.type]} on ${s}.`;
        }
        break;
      }
    }
    return void 0;
  }
  function discoveredPoint(fenBefore, uci) {
    const c = new Chess(fenBefore);
    const m = apply(c, uci);
    if (!m || m.flags.includes("k") || m.flags.includes("q")) return void 0;
    if (c.isCheckmate()) return void 0;
    for (const row of c.board()) {
      for (const cell of row) {
        if (!cell || cell.color !== m.color || cell.square === m.to) continue;
        const dirs = sliderDirs(cell.type);
        if (!dirs) continue;
        for (const dir of dirs) {
          let passedFrom = false;
          for (const s of raySquares(cell.square, dir)) {
            if (s === m.from) {
              passedFrom = true;
              continue;
            }
            const p = c.get(s);
            if (!p) continue;
            if (!passedFrom) break;
            if (p.color !== m.color && p.type === "k") {
              return `${m.san} discovers check from the ${NAME[cell.type]} on ${cell.square}.`;
            }
            if (p.color !== m.color && VAL[p.type] >= 3 && (VAL[p.type] > VAL[cell.type] || c.attackers(s, p.color).length === 0)) {
              return `${m.san} uncovers the ${NAME[cell.type]} on ${cell.square}'s attack on the ${NAME[p.type]} on ${s}.`;
            }
            break;
          }
        }
      }
    }
    return void 0;
  }
  function trappedPoint(fenBefore, uci) {
    const c = new Chess(fenBefore);
    const m = apply(c, uci);
    if (!m) return void 0;
    if (c.isCheck()) return void 0;
    const us = m.color;
    const them = us === "w" ? "b" : "w";
    const isTrappedOn = (board, sq, type) => {
      const attackerTypes = (s, by) => board.attackers(s, by).map((a) => board.get(a)?.type ?? "k");
      const minAttackerVal = (s, by) => {
        const vals = attackerTypes(s, by).filter((t) => t !== "k").map((t) => VAL[t]);
        return vals.length ? Math.min(...vals) : Infinity;
      };
      const forced = minAttackerVal(sq, us) < VAL[type] || attackerTypes(sq, us).length > 0 && board.attackers(sq, them).length === 0;
      if (!forced) return false;
      const escapes = board.moves({ square: sq, verbose: true });
      return escapes.every((e) => {
        const grabbed = board.get(e.to);
        if (grabbed && grabbed.color === us && VAL[grabbed.type] >= VAL[type]) {
          return false;
        }
        if (attackerTypes(e.to, us).length === 0) return false;
        if (minAttackerVal(e.to, us) < VAL[type]) return true;
        const defenders = board.attackers(e.to, them).filter((d) => d !== sq);
        return defenders.length === 0;
      });
    };
    let pre = null;
    try {
      const parts = fenBefore.split(" ");
      parts[1] = them;
      parts[3] = "-";
      pre = new Chess(parts.join(" "));
    } catch {
      pre = null;
    }
    const candidates = [];
    for (const row of c.board()) {
      for (const cell of row) {
        if (cell && cell.color !== us && VAL[cell.type] >= 3 && cell.type !== "k") {
          candidates.push({ sq: cell.square, type: cell.type });
        }
      }
    }
    candidates.sort((a, b) => VAL[b.type] - VAL[a.type]);
    for (const x of candidates) {
      if (!isTrappedOn(c, x.sq, x.type)) continue;
      if (pre && !isTrappedOn(pre, x.sq, x.type)) {
        return `${m.san} traps the ${NAME[x.type]} on ${x.sq} \u2014 it has no safe square.`;
      }
    }
    return void 0;
  }
  function freeCapturePoint(fenBefore, uci) {
    const c = new Chess(fenBefore);
    const mover = c.turn();
    const target = uci.slice(2, 4);
    const victim = c.get(target);
    if (!victim || victim.type === "p") return void 0;
    if (c.attackers(target, victim.color).length > 0) return void 0;
    const m = apply(c, uci);
    if (!m || !m.captured) return void 0;
    if (c.isCheckmate()) return void 0;
    void mover;
    return `${m.san} simply wins the ${NAME[victim.type]} \u2014 it's undefended.`;
  }
  function mateBoard(fenBefore, pv) {
    const c = new Chess(fenBefore);
    for (const u of pv.slice(0, 24)) {
      if (!apply(c, u)) return void 0;
      if (c.isCheckmate()) return c;
    }
    return void 0;
  }
  function matePattern(mated) {
    const loser = mated.turn();
    const winner = loser === "w" ? "b" : "w";
    let ksq;
    for (const row of mated.board()) {
      for (const cell of row) {
        if (cell && cell.type === "k" && cell.color === loser) ksq = cell.square;
      }
    }
    if (!ksq) return void 0;
    const kf = ksq.charCodeAt(0) - 97;
    const kr = Number(ksq[1]) - 1;
    const ownBlocked = (s) => {
      const p = mated.get(s);
      return !!p && p.color === loser;
    };
    const checkers = mated.attackers(ksq, winner);
    if (checkers.length === 1 && mated.get(checkers[0])?.type === "n") {
      const neighbours = [];
      for (let df = -1; df <= 1; df++) {
        for (let dr = -1; dr <= 1; dr++) {
          if (!df && !dr) continue;
          const s = toSquare(kf + df, kr + dr);
          if (s) neighbours.push(s);
        }
      }
      if (neighbours.every(ownBlocked)) return "smothered";
    }
    const backRank = loser === "w" ? 0 : 7;
    if (kr !== backRank) return void 0;
    const alongRank = checkers.some((s) => {
      const t = mated.get(s)?.type;
      return (t === "r" || t === "q") && Number(s[1]) - 1 === backRank;
    });
    if (!alongRank) return void 0;
    const fwd = loser === "w" ? 1 : -1;
    for (let df = -1; df <= 1; df++) {
      const s = toSquare(kf + df, kr + fwd);
      if (s && !ownBlocked(s)) return void 0;
    }
    return "back-rank";
  }
  function mateGarnish(mated, sep = " \u2014 a ") {
    const pat = mated ? matePattern(mated) : void 0;
    return pat ? `${sep}${pat} mate` : "";
  }
  function promotionPoint(fenBefore, pv) {
    const c = new Chess(fenBefore);
    const mover = c.turn();
    const window = pv.slice(0, 9);
    for (let i = 0; i < window.length; i++) {
      const m = apply(c, window[i]);
      if (!m) return void 0;
      if (m.color !== mover || !m.promotion) continue;
      let sq = m.to;
      const probe = new Chess(c.fen());
      for (const u of window.slice(i + 1)) {
        const r = apply(probe, u);
        if (!r) break;
        if (sq && r.from === sq && r.color === mover) sq = r.to;
        else if (sq && r.to === sq && r.captured) return void 0;
      }
      return `${sanLine(fenBefore, pv, i + 1)} makes a new ${NAME[m.promotion]}.`;
    }
    return void 0;
  }
  function sacrificeStory(fenBefore, pv) {
    const c = new Chess(fenBefore);
    const mover = c.turn();
    const window = pv.slice(0, 9);
    let net = 0;
    let minNet = 0;
    let piece;
    for (let i = 0; i < window.length; i++) {
      const m = apply(c, window[i]);
      if (!m) break;
      if (m.captured) net += m.color === mover ? VAL[m.captured] : -VAL[m.captured];
      if (m.promotion) net += (m.color === mover ? 1 : -1) * (VAL[m.promotion] - 1);
      if (m.color !== mover) {
        if (i === 1 && m.captured && m.to === window[0]?.slice(2, 4) && window[0].length < 5) {
          piece = NAME[m.captured];
        }
        if (net < minNet) minNet = net;
      }
    }
    if (minNet > -2) return void 0;
    const mated = mateBoard(fenBefore, pv);
    const mates = !!mated && mated.turn() !== mover;
    const payoff = quietMaterialOverLine(fenBefore, window);
    if (!mates && payoff.net < 2) return void 0;
    return { piece, mates, net: payoff.net, plies: payoff.plies };
  }
  function explainMove(input) {
    const { fenBefore, playedUci, refutationPv, bestUci, bestPv, playedMate, bestMate, isBest } = input;
    if (isBest) return {};
    const out = {};
    const playedLine = [playedUci, ...refutationPv];
    if (playedMate !== null && playedMate < 0) {
      const n = Math.abs(playedMate);
      const refSans = getSanLine(fenBefore, playedLine.slice(0, 2)).map((s) => s.san);
      const garnish = mateGarnish(mateBoard(fenBefore, playedLine), n === 1 ? ", a " : " \u2014 a ");
      out.playedIssue = n === 1 && refSans[1] ? `This allows immediate mate \u2014 ${refSans[1]}${garnish}.` : `This allows a forced mate in ${n}${refSans[1] ? `, starting with ${refSans[1]}` : ""}${garnish}.`;
    } else {
      out.playedIssue = hangingIssue(fenBefore, playedUci, refutationPv[0]);
      if (!out.playedIssue && refutationPv.length > 0) {
        const { net, plies, pawnsOnly } = quietMaterialOverLine(fenBefore, playedLine.slice(0, 9));
        if (net <= -1) {
          const fenAfter = getFenAfter(fenBefore, playedUci);
          const continuation = fenAfter ? getNumberedSanLine(fenAfter, playedLine.slice(1, plies)) : "";
          if (continuation) {
            out.playedIssue = net <= -2 ? `This loses material \u2014 after ${continuation}, you're down ${-net} points.` : pawnsOnly ? `This loses a pawn \u2014 after ${continuation}, you're a pawn down.` : `This loses material \u2014 after ${continuation}, you come out a point down.`;
          }
        }
      }
      if (!out.playedIssue && refutationPv.length > 0) {
        const story = summarizeLine(fenBefore, playedLine.slice(0, 9));
        if (story) out.lineStory = `In this line, ${story}.`;
      }
    }
    if (refutationPv.length > 0) {
      out.evidence = { fen: fenBefore, ucis: playedLine.slice(0, 9) };
    }
    if (bestMate !== null && bestMate > 0 && !(playedMate !== null && playedMate > 0)) {
      const bestSan = getSanLine(fenBefore, [bestUci])[0]?.san ?? bestUci;
      const garnish = mateGarnish(mateBoard(fenBefore, bestPv));
      const sac = bestMate > 1 ? sacrificeStory(fenBefore, bestPv) : void 0;
      const sacTxt = sac ? `sacrifices ${sac.piece ? `the ${sac.piece}` : "material"} and ` : "";
      out.bestPoint = bestMate === 1 ? `${bestSan} was immediate checkmate${garnish}.` : `${bestSan} ${sacTxt}forces mate in ${bestMate}${garnish}.`;
    } else {
      out.bestPoint = bestMovePoint(fenBefore, bestUci, bestPv);
    }
    return out;
  }
  function bestMovePoint(fenBefore, bestUci, bestPv) {
    {
      const post = new Chess(fenBefore);
      const m = apply(post, bestUci);
      if (m && post.isCheckmate()) return `${m.san} is checkmate${mateGarnish(post)}.`;
    }
    const point = forkPoint(fenBefore, bestUci) ?? freeCapturePoint(fenBefore, bestUci) ?? pinOrSkewerPoint(fenBefore, bestUci) ?? discoveredPoint(fenBefore, bestUci) ?? trappedPoint(fenBefore, bestUci);
    if (point) return point;
    if (bestPv.length > 1) {
      const sac = sacrificeStory(fenBefore, bestPv);
      if (sac && !sac.mates) {
        return `Instead, ${sanLine(fenBefore, bestPv, sac.plies)} sacrifices ${sac.piece ? `the ${sac.piece}` : "material"} but comes out ${sac.net} point${sac.net === 1 ? "" : "s"} ahead.`;
      }
      const promo = promotionPoint(fenBefore, bestPv);
      if (promo) return promo;
      const { net, plies, pawnsOnly } = quietMaterialOverLine(fenBefore, bestPv.slice(0, 9));
      if (net >= 2) {
        return `Instead, ${sanLine(fenBefore, bestPv, plies)} wins ${net} points of material.`;
      }
      if (net === 1) {
        return pawnsOnly ? `Instead, ${sanLine(fenBefore, bestPv, plies)} wins a pawn.` : `Instead, ${sanLine(fenBefore, bestPv, plies)} wins a point of material.`;
      }
    }
    return void 0;
  }
  var MOTIF_TAGS_VERSION = 4;
  function motifTags(fenBefore, uci, pv, mate) {
    const tags = [];
    const post = new Chess(fenBefore);
    const matesNow = !!apply(post, uci) && post.isCheckmate();
    const patternTag = (mated) => {
      const pat = mated ? matePattern(mated) : void 0;
      return pat ? [`${pat} mate`] : [];
    };
    if (matesNow) return ["mate", ...patternTag(post)];
    const mateKnown = mate !== null && mate > 0;
    if (mateKnown) tags.push("mate", ...patternTag(mateBoard(fenBefore, pv)));
    if (forkPoint(fenBefore, uci)) tags.push("fork");
    if (freeCapturePoint(fenBefore, uci)) tags.push("free capture");
    if (!mateKnown) {
      const ps = pinOrSkewerPoint(fenBefore, uci);
      if (ps) tags.push(ps.includes("skewers") ? "skewer" : "pin");
      if (trappedPoint(fenBefore, uci)) tags.push("trapped piece");
    }
    if (discoveredPoint(fenBefore, uci)) tags.push("discovered attack");
    if (pv.length > 1 && sacrificeStory(fenBefore, pv)) tags.push("sacrifice");
    if (pv.length > 0 && promotionPoint(fenBefore, pv)) tags.push("promotion");
    if (tags.length === 0 && pv.length > 1 && quietMaterialOverLine(fenBefore, pv.slice(0, 9)).net >= 2) {
      tags.push("material");
    }
    return tags;
  }
  function explainGoodMove(fenBefore, playedUci, playedPv, playedMate) {
    const evidence = (plies) => ({ fen: fenBefore, ucis: playedPv.slice(0, plies) });
    const post = new Chess(fenBefore);
    const matesNow = !!apply(post, playedUci) && post.isCheckmate();
    if (playedMate !== null && playedMate > 0 || matesNow) {
      const san = getSanLine(fenBefore, [playedUci])[0]?.san ?? playedUci;
      const garnish = mateGarnish(matesNow ? post : mateBoard(fenBefore, playedPv));
      return {
        text: matesNow || playedMate === 1 ? `${san} is checkmate${garnish}.` : `${san} forces mate in ${playedMate}${garnish}.`,
        evidence: evidence(12)
      };
    }
    const point = forkPoint(fenBefore, playedUci) ?? freeCapturePoint(fenBefore, playedUci) ?? pinOrSkewerPoint(fenBefore, playedUci) ?? discoveredPoint(fenBefore, playedUci) ?? trappedPoint(fenBefore, playedUci);
    if (point) return { text: point, evidence: evidence(1) };
    if (playedPv.length > 1) {
      const sac = sacrificeStory(fenBefore, playedPv);
      if (sac && !sac.mates) {
        return {
          text: `It sacrifices ${sac.piece ? `the ${sac.piece}` : "material"} but comes out ${sac.net} point${sac.net === 1 ? "" : "s"} ahead (${sanLine(fenBefore, playedPv, sac.plies)}).`,
          evidence: evidence(sac.plies)
        };
      }
      const promo = promotionPoint(fenBefore, playedPv);
      if (promo) return { text: promo, evidence: evidence(9) };
      const { net, plies, pawnsOnly } = quietMaterialOverLine(fenBefore, playedPv.slice(0, 9));
      if (net >= 1) {
        const fenAfter = getFenAfter(fenBefore, playedUci);
        const continuation = fenAfter ? getNumberedSanLine(fenAfter, playedPv.slice(1, plies)) : "";
        if (continuation) {
          return {
            text: net >= 2 ? `It wins ${net} points of material (${continuation}).` : pawnsOnly ? `It wins a pawn (${continuation}).` : `It wins a point of material (${continuation}).`,
            evidence: evidence(plies)
          };
        }
      }
      const story = summarizeLine(fenBefore, playedPv.slice(0, 9));
      if (story) return { text: `In this line, ${story}.`, evidence: evidence(9) };
    }
    return void 0;
  }

  // brain/engine/insights.ts
  function lineCp(l) {
    if (l.mate !== null) return l.mate > 0 ? 9999 : -9999;
    return l.score * 100;
  }
  function winChance(evalPawns, mate) {
    if (mate !== null) return mate > 0 ? 100 : 0;
    if (evalPawns === null) return 50;
    const cp = Math.max(-1500, Math.min(1500, evalPawns * 100));
    return 50 + 50 * (2 / (1 + Math.exp(-368208e-8 * cp)) - 1);
  }
  function whitePovWinChance(color, evalPawns, mate) {
    const wc = winChance(evalPawns, mate);
    return color === "w" ? wc : 100 - wc;
  }
  function gradeMove(ply, fenBefore, san, uci, color, lines) {
    if (lines.length === 0) return null;
    const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);
    const cps = sorted.map(lineCp);
    const maxCp = Math.max(...cps);
    const exps = cps.map((c) => Math.exp((c - maxCp) / 100));
    const denom = exps.reduce((a, b) => a + b, 0) || 1;
    const confs = exps.map((e) => e / denom * 100);
    const bestConf = Math.max(...confs);
    const idx = sorted.findIndex((l) => l.pv[0] === uci);
    const best = sorted[0];
    return {
      ply,
      fenBefore,
      san,
      uci,
      color,
      depth: best.depth,
      rank: idx >= 0 ? idx + 1 : null,
      evalPawns: idx >= 0 ? sorted[idx].score : null,
      mate: idx >= 0 ? sorted[idx].mate : null,
      pctBest: idx >= 0 && bestConf > 0 ? confs[idx] / bestConf * 100 : null,
      isBest: idx === 0,
      bestSan: getSan(fenBefore, best.pv[0]),
      bestUci: best.pv[0],
      bestEval: best.score,
      bestMate: best.mate,
      totalLines: sorted.length,
      offList: idx < 0,
      backfilled: false,
      preLines: sorted.map((l, i) => ({ uci: l.pv[0], cp: cps[i] })),
      bestPv: best.pv
    };
  }
  function backfillGrade(grade, childLines) {
    if (childLines.length === 0) return grade;
    const child = [...childLines].sort((a, b) => a.multipv - b.multipv)[0];
    const cp = -(child.mate !== null ? child.mate > 0 ? 9999 : -9999 : child.score * 100);
    const mate = child.mate !== null ? -child.mate : null;
    const others = grade.preLines.filter((l) => l.uci !== grade.uci);
    const pool = [...others.map((l) => l.cp), cp];
    const maxCp = Math.max(...pool);
    const exps = pool.map((c) => Math.exp((c - maxCp) / 100));
    const played = exps[exps.length - 1];
    const pctBest = Math.min(100, played / Math.max(...exps) * 100);
    const rank2 = 1 + others.filter((l) => l.cp > cp).length;
    const isBest = grade.isBest || pctBest >= 100;
    const playedPv = [grade.uci, ...child.pv];
    const wcBest = winChance(grade.bestEval, grade.bestMate);
    const wcPlayed = winChance(cp / 100, mate);
    const drop = Math.max(0, wcBest - wcPlayed);
    const bestWinsMaterial = isCapture(grade.fenBefore, grade.bestUci) && materialOverLine(grade.fenBefore, grade.bestPv.slice(0, 6)) >= 2;
    const missed = !isBest && bestWinsMaterial && drop >= 10 && wcPlayed >= 40;
    let label;
    if (missed) label = "miss";
    else if (drop >= 20) label = "blunder";
    else if (drop >= 10) label = "mistake";
    else if (drop >= 5) label = "inaccuracy";
    else if (!isBest) label = drop <= 2 ? "excellent" : "good";
    else {
      const shortNet = materialOverLine(grade.fenBefore, playedPv.slice(0, 4));
      const others2 = grade.preLines.filter((l) => l.uci !== grade.bestUci);
      const secondCp = others2.length > 0 ? Math.max(...others2.map((l) => l.cp)) : null;
      const wcSecond = secondCp === null ? null : winChance(secondCp / 100, null);
      if (shortNet <= -2 && wcPlayed >= 55 && wcBest <= 92) label = "brilliant";
      else if (wcSecond !== null && wcBest - wcSecond >= 15) label = "great";
      else label = "best";
    }
    let explanation;
    if (child.depth >= 10) {
      if (isBest || pctBest >= 90) {
        const point = explainGoodMove(grade.fenBefore, grade.uci, playedPv, mate);
        explanation = point ? { playedPoint: point.text, evidence: point.evidence } : void 0;
      } else {
        explanation = explainMove({
          fenBefore: grade.fenBefore,
          playedUci: grade.uci,
          refutationPv: child.pv.slice(0, 8),
          bestUci: grade.bestUci,
          bestPv: grade.bestPv,
          playedMate: mate,
          bestMate: grade.bestMate,
          isBest
        });
      }
    }
    return {
      ...grade,
      depth: child.depth,
      evalPawns: mate !== null ? grade.evalPawns : cp / 100,
      mate,
      pctBest,
      rank: rank2,
      isBest,
      backfilled: true,
      explanation,
      label
    };
  }

  // brain/engine/botRecipe.ts
  function specToRecipe(spec) {
    if (spec.kind === "sampler") {
      return {
        options: [["MultiPV", "24"]],
        go: `go depth ${spec.depth}`,
        sample: true,
        alpha: spec.alpha
      };
    }
    if (spec.kind === "skill") {
      return {
        options: [
          ["MultiPV", "1"],
          ["Skill Level", String(spec.level)]
        ],
        go: `go depth ${spec.depth}`,
        sample: false
      };
    }
    return {
      options: [
        ["MultiPV", "1"],
        ["UCI_LimitStrength", "true"],
        ["UCI_Elo", String(Math.max(1320, Math.min(3190, spec.elo)))]
      ],
      go: `go movetime ${spec.movetimeMs}`,
      sample: false
    };
  }
  function parseSpec(id) {
    const parts = id.split(":");
    if (parts[0] === "sampler") {
      return {
        kind: "sampler",
        alpha: Number(parts[1].replace("a", "")),
        depth: Number(parts[2].replace("d", ""))
      };
    }
    if (parts[0] === "skill") {
      return { kind: "skill", level: Number(parts[1]), depth: Number(parts[2].replace("d", "")) };
    }
    if (parts[0] === "ucielo") {
      return {
        kind: "ucielo",
        elo: Number(parts[1]),
        movetimeMs: Number(parts[2].replace("mt", ""))
      };
    }
    return botSpec(Number(id));
  }
  var NATIVE = {
    // SAMPLER refined 2026-07-13 from a 2,600-game high-N ladder
    // (data/bot-native-hisample.json). The original n=40 fit ran ~85 Elo weak
    // across 100–1300 (slider-1000 actually played ~900); n=200 caught the
    // systematic tilt and the knots now invert to identity (700–2100 within
    // ±45). The UCI_Elo top band is still the n=40 fit (movetime = expensive).
    sampler: [
      { e: -153, alpha: 0.1, depth: 1 },
      { e: 155, alpha: 0.3, depth: 1 },
      { e: 495, alpha: 0.5, depth: 2 },
      { e: 773, alpha: 0.7, depth: 2 },
      { e: 1161, alpha: 1.2, depth: 2 },
      { e: 1627, alpha: 2, depth: 2 },
      { e: 2033, alpha: 4, depth: 2 },
      { e: 2327, alpha: 8, depth: 2 }
    ],
    // UCI_Elo band refined 2026-07-13 from a 1,000-game n=200 movetime ladder
    // (data/bot-native-mt200.json) — the original was an n=40 fit
    ucielo: [
      { e: 2048, elo: 2400, movetimeMs: 400 },
      { e: 2468, elo: 2800, movetimeMs: 400 },
      { e: 2824, elo: 3190, movetimeMs: 400 }
    ],
    samplerMax: 2100,
    depthBoundary: 410,
    eloMin: 100,
    eloMax: 2800
  };
  var WASM = {
    sampler: [
      { e: 87, alpha: 0.1, depth: 1 },
      { e: 416, alpha: 0.3, depth: 1 },
      { e: 732, alpha: 0.5, depth: 2 },
      { e: 968, alpha: 0.7, depth: 2 },
      { e: 1397, alpha: 1.2, depth: 2 },
      { e: 1812, alpha: 2, depth: 2 },
      { e: 2239, alpha: 4, depth: 2 },
      { e: 2485, alpha: 8, depth: 2 }
    ],
    // UCI_Elo band refined 2026-07-13 from an 800-game n=200 movetime ladder
    // (data/bot-wasm-mt200.json); the 3190 knot is extrapolated (the slider
    // caps at 2800 so it's only the top bracket, never reached)
    ucielo: [
      { e: 2297, elo: 2400, movetimeMs: 400 },
      { e: 2574, elo: 2800, movetimeMs: 400 },
      { e: 3436, elo: 3190, movetimeMs: 400 }
    ],
    // sampler covers cleanly up to a8 (2485); UCI_Elo takes only the top above it
    samplerMax: 2485,
    depthBoundary: 550,
    eloMin: 100,
    eloMax: 2800
  };
  var BANDS = { native: NATIVE, wasm: WASM };
  var activeSubstrate = "wasm";
  function setBotSubstrate(s) {
    activeSubstrate = s;
  }
  function getBotSubstrate() {
    return activeSubstrate;
  }
  function botEloMin(s = activeSubstrate) {
    return BANDS[s].eloMin;
  }
  function botEloMax(s = activeSubstrate) {
    return BANDS[s].eloMax;
  }
  function lerp(x, x0, x1, y0, y1) {
    const t = x1 === x0 ? 0 : (x - x0) / (x1 - x0);
    return y0 + t * (y1 - y0);
  }
  function botSpec(elo, s = activeSubstrate) {
    const b = BANDS[s];
    const e = Math.max(b.eloMin, Math.min(b.eloMax, elo));
    if (e <= b.samplerMax) {
      return { kind: "sampler", alpha: samplerAlphaFor(e, s), depth: e < b.depthBoundary ? 1 : 2 };
    }
    const k = b.ucielo;
    if (e <= k[0].e) return { kind: "ucielo", elo: k[0].elo, movetimeMs: k[0].movetimeMs };
    for (let i = 0; i + 1 < k.length; i++) {
      if (e <= k[i + 1].e) {
        return {
          kind: "ucielo",
          elo: Math.round(lerp(e, k[i].e, k[i + 1].e, k[i].elo, k[i + 1].elo)),
          movetimeMs: k[i].movetimeMs
        };
      }
    }
    const top = k[k.length - 1];
    return { kind: "ucielo", elo: top.elo, movetimeMs: top.movetimeMs };
  }
  function samplerAlphaFor(elo, s = activeSubstrate) {
    const b = BANDS[s];
    const e = Math.max(b.eloMin, Math.min(b.eloMax, elo));
    const k = b.sampler;
    if (e <= k[0].e) return k[0].alpha;
    for (let i = 0; i + 1 < k.length; i++) {
      if (e <= k[i + 1].e) {
        return Math.exp(lerp(e, k[i].e, k[i + 1].e, Math.log(k[i].alpha), Math.log(k[i + 1].alpha)));
      }
    }
    return k[k.length - 1].alpha;
  }
  function botRecipe(elo, s = activeSubstrate) {
    return specToRecipe(botSpec(elo, s));
  }

  // brain/bot.ts
  function lineCp2(l) {
    if (l.mate !== null) return l.mate > 0 ? 9999 : -9999;
    return l.score * 100;
  }
  function moveWin(l) {
    return winChance(l.mate === null ? l.score : null, l.mate);
  }
  function clamp01(x) {
    return Math.max(0, Math.min(1, x));
  }
  function selectBotMove(lines, elo, alpha) {
    if (lines.length === 0) return null;
    const sorted = [...lines].sort((a2, b) => a2.multipv - b.multipv);
    const mates = sorted.filter((l) => l.mate !== null && l.mate > 0);
    if (mates.length > 0) {
      const quickest = mates.reduce((a2, b) => a2.mate <= b.mate ? a2 : b);
      const pSeeMate = 0.05 + 0.95 * clamp01((elo - 100) / (3e3 - 100));
      if (Math.random() < pSeeMate) return quickest.pv[0];
    }
    const cps = sorted.map(lineCp2);
    const maxCp = Math.max(...cps);
    const exps = cps.map((c) => Math.exp((c - maxCp) / 100));
    const denom = exps.reduce((a2, b) => a2 + b, 0) || 1;
    const confs = exps.map((e) => e / denom * 100);
    const bestIdx = confs.indexOf(Math.max(...confs));
    const bestConf = confs[bestIdx];
    if (elo >= 2e3 && sorted.length > 1) {
      const secondBest = Math.max(...confs.filter((_, i) => i !== bestIdx));
      if (secondBest / bestConf * 100 < 20) return sorted[bestIdx].pv[0];
    }
    const a = alpha ?? 0.8 + clamp01((elo - 800) / (3600 - 800)) * 7.2;
    let probs = confs.map((c) => Math.pow(Math.max(c, 1e-6) / 100, a));
    if (elo >= 2200) {
      probs = probs.map((p, i) => {
        const pctBest = confs[i] / bestConf * 100;
        return p * (pctBest < 60 ? 0.2 : pctBest < 75 ? 0.5 : 1);
      });
    }
    const sum = probs.reduce((a2, b) => a2 + b, 0);
    if (!(sum > 0)) return sorted[0].pv[0];
    let r = Math.random() * sum;
    for (let i = 0; i < sorted.length; i++) {
      r -= probs[i];
      if (r <= 0) return sorted[i].pv[0];
    }
    return sorted[sorted.length - 1].pv[0];
  }
  function shapedParams(elo) {
    const t = clamp01((1600 - elo) / 1e3);
    return {
      missProb: 0.04 + 0.56 * t,
      // 4% at 1600 → ~38% at 1000 → 60% at 600
      tacticalGapPct: 15,
      temperature: 1.5 + 10.5 * t,
      // 1.5 at 1600 → 12 at 600
      quietWindowPct: 6 + 24 * t
      // 6 at 1600 → 30 at 600
    };
  }
  var PIECE_VAL2 = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
  var SCAN_MULTS = {
    mateSoon: 0.04,
    recapture: 0.02,
    grab: 0.03,
    capture: 0.08,
    check: 0.1,
    quiet: 2.8,
    quietShallow: 0.98,
    sac: 1.5,
    deepBase: 0.96,
    deepSlope: 0.5,
    deepCap: 2.8,
    pCap: 0.97
  };
  function tacticVisibility(fen, pv, mate, discoveryDepth, m = SCAN_MULTS, lastMoveTo) {
    if (mate !== null && mate > 0 && mate <= 2) return { multiplier: m.mateSoon, kind: "mate-soon" };
    if (lastMoveTo && pv[0]?.slice(2, 4) === lastMoveTo) {
      try {
        const probe = new Chess(fen);
        const mv = probe.move({
          from: pv[0].slice(0, 2),
          to: pv[0].slice(2, 4),
          promotion: pv[0].length > 4 ? pv[0][4] : void 0
        });
        if (mv.captured) return { multiplier: m.recapture, kind: "recapture" };
      } catch {
      }
    }
    if (discoveryDepth !== void 0 && discoveryDepth >= 2) {
      return {
        multiplier: Math.min(m.deepBase + m.deepSlope * (discoveryDepth - 1), m.deepCap),
        kind: `deep-d${discoveryDepth}`
      };
    }
    try {
      const c = new Chess(fen);
      const mover = c.turn();
      const balance = () => {
        let v2 = 0;
        for (const row of c.board())
          for (const sq of row) if (sq) v2 += (sq.color === mover ? 1 : -1) * PIECE_VAL2[sq.type];
        return v2;
      };
      const start = balance();
      let firstCaptureVal = 0;
      let givesCheck = false;
      let settledMin = 0;
      let finalGain = 0;
      for (let i = 0; i < Math.min(pv.length, 10); i++) {
        const uci = pv[i];
        const m2 = c.move({
          from: uci.slice(0, 2),
          to: uci.slice(2, 4),
          promotion: uci.length > 4 ? uci[4] : void 0
        });
        if (i === 0) {
          firstCaptureVal = m2.captured ? PIECE_VAL2[m2.captured] : 0;
          givesCheck = c.inCheck();
        }
        const gain = balance() - start;
        if (i % 2 === 1) settledMin = Math.min(settledMin, gain);
        finalGain = gain;
      }
      const shallow = discoveryDepth !== void 0;
      let v;
      if (firstCaptureVal >= 5 && finalGain >= 3)
        v = { multiplier: m.grab, kind: "grab" };
      else if (firstCaptureVal > 0 && finalGain >= 1)
        v = { multiplier: m.capture, kind: "winning-capture" };
      else if (givesCheck) v = { multiplier: m.check, kind: "check" };
      else v = { multiplier: shallow ? m.quietShallow : m.quiet, kind: "quiet" };
      if (settledMin <= -2 && !shallow) {
        v = { multiplier: Math.min(v.multiplier * m.sac, m.deepCap), kind: `${v.kind}-sac` };
      }
      return v;
    } catch {
      return { multiplier: 1, kind: "unknown" };
    }
  }
  function openingDamp(fen) {
    const moveNo = Number(fen.split(" ")[5]) || 20;
    return clamp01(0.3 + 0.7 * (moveNo - 1) / 8);
  }
  function scanSkill(elo) {
    return clamp01((elo - 350) / 550);
  }
  function bySkill(factor, skill) {
    return factor >= 1 ? factor : 1 + (factor - 1) * skill;
  }
  function hash01(key) {
    let h = 2166136261;
    for (let i = 0; i < key.length; i++) {
      h ^= key.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return (h >>> 0) / 4294967296;
  }
  function softmaxPick(cands, temperature, factors) {
    const maxWin = Math.max(...cands.map((c) => c.win));
    const weights = cands.map(
      (c, i) => Math.exp((c.win - maxWin) / Math.max(temperature, 0.1)) * (factors?.[i] ?? 1)
    );
    const total = weights.reduce((a, b) => a + b, 0);
    let r = Math.random() * total;
    for (let k = 0; k < cands.length; k++) {
      r -= weights[k];
      if (r <= 0) return cands[k].move;
    }
    return cands[cands.length - 1].move;
  }
  function dangerVisibility(fen, uci) {
    try {
      const c = new Chess(fen);
      const moved = c.move({
        from: uci.slice(0, 2),
        to: uci.slice(2, 4),
        promotion: uci.length > 4 ? uci[4] : void 0
      });
      const dest = moved.to;
      const movedVal = PIECE_VAL2[moved.promotion ?? moved.piece];
      let cheapest = Infinity;
      let canRecapture = false;
      for (const reply of c.moves({ verbose: true })) {
        if (reply.to === dest && reply.captured)
          cheapest = Math.min(cheapest, PIECE_VAL2[reply.piece]);
      }
      if (cheapest === Infinity) return 1;
      const probe = new Chess(c.fen());
      const attacker = probe.moves({ verbose: true }).find((m) => m.to === dest && m.captured);
      if (attacker) {
        probe.move(attacker);
        canRecapture = probe.moves({ verbose: true }).some((m) => m.to === dest && m.captured);
      }
      if (cheapest < movedVal - 1) return 0.05;
      if (!canRecapture && movedVal >= 3) return 0.1;
      return 1;
    } catch {
      return 1;
    }
  }
  function shapedBotMove(lines, elo, params, seed, fen, discoveryDepth, lastMoveTo) {
    if (lines.length === 0) return null;
    const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);
    const best = sorted[0];
    if (sorted.length === 1) return best.pv[0];
    const { missProb, tacticalGapPct, temperature, quietWindowPct, scan, scanMults } = {
      ...shapedParams(elo),
      ...params
    };
    const scanning = !!scan && !!fen;
    const skill = scanning ? scanSkill(elo) : 1;
    const damp = scanning ? bySkill(openingDamp(fen), skill) : 1;
    const wins = sorted.map(moveWin);
    const bestWin = wins[0];
    let missedVisibleBest = false;
    if (scanning) {
      const mults = { ...SCAN_MULTS, ...scanMults };
      const vis = tacticVisibility(fen, best.pv, best.mate, discoveryDepth, mults, lastMoveTo);
      if (vis.kind === "recapture" || vis.kind === "grab") {
        const s = vis.kind === "recapture" ? Math.max(skill, 0.7) : skill;
        const p = Math.min(missProb * bySkill(vis.multiplier, s) * damp, mults.pCap);
        const roll = seed !== void 0 ? hash01(`${seed}:${best.pv[0].slice(2, 4)}`) : Math.random();
        if (roll >= p) return best.pv[0];
        missedVisibleBest = true;
      }
    }
    if (bestWin >= 90 && wins[1] >= 85) {
      const cands2 = [];
      for (let i = 0; i < sorted.length; i++) {
        if (i === 0 && missedVisibleBest) continue;
        if (wins[i] < 85) continue;
        const l = sorted[i];
        const v = l.mate !== null && l.mate > 0 ? 25 - Math.min(l.mate, 15) : l.score;
        cands2.push({ move: l.pv[0], win: v });
      }
      if (cands2.length > 0)
        return softmaxPick(
          cands2,
          temperature / 4,
          scanning ? cands2.map((c) => bySkill(dangerVisibility(fen, c.move), skill)) : void 0
        );
    }
    if (bestWin - wins[1] >= tacticalGapPct) {
      if (!missedVisibleBest) {
        const mateSoon = best.mate !== null && best.mate > 0 && best.mate <= 2;
        let p = mateSoon ? missProb * 0.25 : missProb;
        if (scanning) {
          const mults = { ...SCAN_MULTS, ...scanMults };
          const vis = tacticVisibility(fen, best.pv, best.mate, discoveryDepth, mults, lastMoveTo);
          const s = vis.kind === "recapture" ? Math.max(skill, 0.7) : skill;
          p = missProb * bySkill(vis.multiplier, s) * damp;
          p = Math.min(p, mults.pCap);
        }
        const roll = seed !== void 0 ? hash01(`${seed}:${best.pv[0].slice(2, 4)}`) : Math.random();
        if (roll >= p) return best.pv[0];
      }
      const rest = sorted.slice(1).map((l, i) => ({ move: l.pv[0], win: wins[i + 1] }));
      return softmaxPick(
        rest,
        temperature,
        scanning ? rest.map((c) => bySkill(dangerVisibility(fen, c.move), skill)) : void 0
      );
    }
    const cands = [];
    for (let i = 0; i < sorted.length; i++) {
      if (i === 0 && missedVisibleBest) continue;
      if (bestWin - wins[i] <= quietWindowPct) cands.push({ move: sorted[i].pv[0], win: wins[i] });
    }
    if (cands.length === 0) return sorted[1].pv[0];
    return softmaxPick(
      cands,
      temperature * damp,
      scanning ? cands.map((c) => bySkill(dangerVisibility(fen, c.move), skill)) : void 0
    );
  }
  var SHAPED_KNOTS_SCAN = {
    // v4.1 (saturated-loss fix INCLUDED — the fix measured +140-220 across the
    // ladder vs the honest ruler; the earlier 'calibration-neutral' claim was
    // falsified by the imitation-experiment's control pair, 2026-07-17).
    // Fresh grid, n=100 everywhere. Floor note: label-600 measures 891
    // internal ≈ display ~650 — display-600 is currently UNREACHABLE; the
    // pre-gate captures ate scanSkill's restored bottom. Params extension
    // below label 600 is the open fix if the roster wants true 600s back.
    wasm: [
      { label: 600, strength: 891 },
      { label: 750, strength: 1051 },
      { label: 900, strength: 1186 },
      { label: 1050, strength: 1327 },
      { label: 1200, strength: 1528 },
      { label: 1350, strength: 1904 },
      { label: 1500, strength: 2319 }
    ],
    // STALE (v4.0): the native grid predates the saturated-loss fix; desktop
    // Squares will play above label until the native re-grid runs. Web ships
    // from the wasm table; re-measure before any Tauri release.
    native: [
      { label: 600, strength: 753 },
      { label: 750, strength: 844 },
      { label: 900, strength: 1024 },
      { label: 1050, strength: 1229 },
      { label: 1200, strength: 1417 },
      { label: 1350, strength: 1650 },
      { label: 1500, strength: 1900 }
    ]
  };
  var BOT_MODEL = "scan";
  var SHAPED_KNOTS = {
    wasm: [
      { label: 600, strength: 768 },
      { label: 750, strength: 904 },
      { label: 900, strength: 1048 },
      { label: 1050, strength: 1225 },
      { label: 1200, strength: 1357 },
      { label: 1350, strength: 1641 },
      { label: 1500, strength: 1971 }
    ],
    native: [
      { label: 600, strength: 756 },
      { label: 750, strength: 815 },
      { label: 900, strength: 982 },
      { label: 1050, strength: 1153 },
      { label: 1200, strength: 1368 },
      { label: 1350, strength: 1639 },
      { label: 1500, strength: 2024 }
    ]
  };
  function shapedStrengthRange(substrate = getBotSubstrate(), model = BOT_MODEL) {
    const k = (model === "scan" ? SHAPED_KNOTS_SCAN : SHAPED_KNOTS)[substrate];
    return { min: k[0].strength, max: k[k.length - 1].strength };
  }
  function shapedLabelFor(targetElo, substrate = getBotSubstrate(), model = BOT_MODEL) {
    const k = (model === "scan" ? SHAPED_KNOTS_SCAN : SHAPED_KNOTS)[substrate];
    if (targetElo <= k[0].strength) return k[0].label;
    if (targetElo >= k[k.length - 1].strength) return k[k.length - 1].label;
    for (let i = 1; i < k.length; i++) {
      if (targetElo <= k[i].strength) {
        const f = (targetElo - k[i - 1].strength) / (k[i].strength - k[i - 1].strength);
        return Math.round(k[i - 1].label + f * (k[i].label - k[i - 1].label));
      }
    }
    return k[k.length - 1].label;
  }
  function shapedSearchDepth(label) {
    return Math.max(4, Math.min(12, Math.round(4 + 8 * (label - 600) / 900)));
  }
  function botDelay(minMs = 300, maxMs = 1e3) {
    return minMs + Math.floor(Math.random() * (maxMs - minMs + 1));
  }

  // brain/repetition.ts
  function posKey(fen) {
    return fen.split(" ").slice(0, 4).join(" ");
  }
  function clearlyWinning(m) {
    return m.mate !== null ? m.mate > 0 : m.score >= 2;
  }
  function keepsTheWin(m) {
    return m.mate !== null ? m.mate > 0 : m.score > 0.5;
  }
  function avoidRepetition(uci, fens, lines) {
    const current = fens.at(-1);
    const best = lines[0];
    if (!current || !best || !clearlyWinning(best)) return uci;
    const counts = /* @__PURE__ */ new Map();
    for (const f of fens) {
      const k = posKey(f);
      counts.set(k, (counts.get(k) ?? 0) + 1);
    }
    const wouldBeThird = (mv) => {
      const after = getFenAfter(current, mv);
      return after !== null && (counts.get(posKey(after)) ?? 0) >= 2;
    };
    if (!wouldBeThird(uci)) return uci;
    const alt = lines.find((l) => l.pv[0] && l.pv[0] !== uci && keepsTheWin(l) && !wouldBeThird(l.pv[0]));
    return alt?.pv[0] ?? uci;
  }

  // brain/bots.ts
  var SCALE_OFFSET = 240;
  function square(displayElo) {
    const label = shapedLabelFor(displayElo + SCALE_OFFSET);
    const missPct = Math.round(shapedParams(label).missProb * 100);
    return {
      id: `square-${displayElo}`,
      name: `Square ${displayElo}`,
      elo: displayElo,
      family: "square",
      blurb: `Plays sound chess but misses ~${missPct}% of tactical moments \u2014 and stays blind to what it hasn't seen.`,
      shapedLabel: label
    };
  }
  function maia(displayElo, band, roman) {
    return {
      id: `maia-${band}`,
      name: `Maia ${roman}`,
      elo: displayElo,
      family: "maia",
      blurb: `A neural net trained to move like real ~${displayElo}-rated players \u2014 human habits, human mistakes.`,
      maiaBand: band
    };
  }
  function maiaSampled(displayElo, band, roman) {
    return {
      id: `maia-s-${band}`,
      name: `Maia ${roman} (sampled)`,
      elo: displayElo,
      family: "maia",
      blurb: `The same net as Maia ${roman}, but drawing from its whole move distribution instead of the consensus move \u2014 weaker, moodier, more like one player than an average. Rating estimated.`,
      maiaBand: band,
      maiaTemp: 1
    };
  }
  function fish(displayElo) {
    return {
      id: `fish-${displayElo}`,
      name: `Fish ${displayElo}`,
      elo: displayElo,
      family: "fish",
      blurb: "Stockfish with the strength limiter on \u2014 cold, accurate, occasionally merciful.",
      numericElo: displayElo + SCALE_OFFSET
    };
  }
  function retro(displayElo, engine, ply, name, blurb) {
    return { id: `retro-${engine}-${ply}`, name, elo: displayElo, family: "retro", blurb, retro: { engine, ply } };
  }
  var RETROS = [
    retro(
      1200,
      "bernstein",
      2,
      "Bernstein 1957",
      'The first complete chess program (IBM 704, 8 minutes a move). Considers only 7 "plausible moves" \u2014 beat it and you beat the dawn of computing.'
    ),
    retro(
      1230,
      "sargon",
      1,
      "Sargon 1978",
      "Dan and Kathe Spracklen's Z80 classic that launched home-computer chess, at its easiest setting: one ply plus exchange sense."
    ),
    retro(
      1300,
      "turochamp",
      1,
      "Turochamp 1948",
      "Alan Turing and David Champernowne's paper machine \u2014 written before computers existed to run it. Turing executed it by hand, one move per half hour."
    )
  ];
  function dala(displayElo, band) {
    return {
      id: `dala-${band}`,
      name: `Dala ${band}`,
      elo: displayElo,
      family: "dala",
      blurb: `A neural net trained only on games by ~${band}-rated humans, playing their moves \u2014 habits, hopes, blind spots and all. (Downloads its brain on first use.)`,
      dalaBand: band,
      nativeOnly: true
    };
  }
  function horizon(displayElo, level) {
    return {
      id: `horizon-${level}`,
      name: `Horizon ${displayElo}`,
      elo: displayElo,
      family: "horizon",
      blurb: level === 1 ? "A tiny JavaScript engine that cannot see past its own captures \u2014 it takes, you take back, it is surprised. The weakest honest engine we could find." : "One ply deeper than its little sibling: still starts exchanges it cannot finish, but needs slightly more convincing.",
      jsceLevel: level
    };
  }
  var GARBO = {
    id: "garbo-2000",
    name: "Garbo 2011",
    elo: 2020,
    family: "garbo",
    blurb: "Gary Linscott's 2011 JavaScript engine, verbatim \u2014 its author went on to build the tools modern chess engines are made with. Plays like 2011: sharp, material-minded, honestly pre-neural.",
    garboMs: 1e3
  };
  var PERSONAS = [
    horizon(550, 1),
    horizon(860, 2),
    ...[600, 700, 800, 900, 1e3, 1100, 1200, 1300, 1400, 1500, 1600, 1700].map(square),
    ...RETROS,
    dala(911, 700),
    dala(1095, 900),
    dala(1315, 1300),
    maiaSampled(1310, 1100, "I"),
    maiaSampled(1380, 1500, "V"),
    maiaSampled(1440, 1900, "IX"),
    maia(1570, 1100, "I"),
    maia(1640, 1500, "V"),
    maia(1700, 1900, "IX"),
    GARBO,
    ...[1800, 1900, 2e3, 2100, 2200, 2300, 2400, 2500].map(fish)
  ].sort((a, b) => a.elo - b.elo || a.name.localeCompare(b.name));
  function availablePersonas(native) {
    return native ? PERSONAS : PERSONAS.filter((p) => !p.nativeOnly);
  }
  var byId = new Map(PERSONAS.map((p) => [p.id, p]));
  function personaById(id) {
    return id && byId.get(id) || null;
  }
  function personaInternalElo(p) {
    return p.elo + SCALE_OFFSET;
  }

  // brain/classifications.ts
  var CLASS = {
    brilliant: { glyph: "\u203C", color: "#1baca6", noun: "brilliant", graphed: true },
    great: { glyph: "!", color: "#5b8bb0", noun: "a great move", graphed: true },
    best: { glyph: "\u2605", color: "#81b64c", noun: "the best move", graphed: false },
    excellent: { glyph: "\u2714", color: "#81b64c", noun: "excellent", graphed: false },
    good: { glyph: "\u2713", color: "#95b776", noun: "a good move", graphed: false },
    inaccuracy: { glyph: "?!", color: "#f0c15c", noun: "an inaccuracy", graphed: true },
    mistake: { glyph: "?", color: "#e6912c", noun: "a mistake", graphed: true },
    miss: { glyph: "\xD7", color: "#d9683a", noun: "a miss", graphed: true },
    blunder: { glyph: "??", color: "#ca3431", noun: "a blunder", graphed: true }
  };
  var LABEL_ORDER = [
    "brilliant",
    "great",
    "best",
    "excellent",
    "good",
    "inaccuracy",
    "mistake",
    "miss",
    "blunder"
  ];

  // brain/engine/threats.ts
  function nullMoveFen(fen) {
    const parts = fen.split(" ");
    if (parts.length < 4) return null;
    parts[1] = parts[1] === "w" ? "b" : "w";
    parts[3] = "-";
    if (parts[4] !== void 0) parts[4] = "0";
    return parts.join(" ");
  }
  var MIN_GAIN = 1;
  function threatProbeFen(fen) {
    let base;
    try {
      base = new Chess(fen);
    } catch {
      return null;
    }
    if (base.isGameOver() || base.inCheck()) return null;
    const nullFen = nullMoveFen(fen);
    if (!nullFen) return null;
    try {
      if (new Chess(nullFen).inCheck()) return null;
    } catch {
      return null;
    }
    return nullFen;
  }
  function judgeThreat(fen, best) {
    const nullFen = threatProbeFen(fen);
    if (!nullFen || !best || best.pv.length === 0) return null;
    if (best.mate !== null) {
      if (best.mate <= 0) return null;
      return {
        fen,
        uci: best.pv[0],
        san: getSan(nullFen, best.pv[0]) ?? best.pv[0],
        gain: Infinity,
        target: kingSquare(fen)
        // the mated side is the side to move in the real position
      };
    }
    const quiet = quietMaterialOverLine(nullFen, best.pv);
    const net = quiet.plies > 0 ? quiet.net : staticFirstCaptureGain(nullFen, best.pv[0]);
    if (net < MIN_GAIN) return null;
    const target = quiet.plies > 0 ? victimSquare(nullFen, best.pv, quiet.plies) : best.pv[0].slice(2, 4);
    return { fen, uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: net, target };
  }
  function kingSquare(fen) {
    const c = new Chess(fen);
    for (const row of c.board()) {
      for (const cell of row) {
        if (cell && cell.type === "k" && cell.color === c.turn()) return cell.square;
      }
    }
    return null;
  }
  function victimSquare(nullFen, ucis, plies) {
    const c = new Chess(nullFen);
    const mover = c.turn();
    const defenderMoves = [];
    for (let i = 0; i < plies; i++) {
      let m;
      try {
        m = c.move({
          from: ucis[i].slice(0, 2),
          to: ucis[i].slice(2, 4),
          promotion: ucis[i].length > 4 ? ucis[i][4] : void 0
        });
      } catch {
        return null;
      }
      if (m.color === mover && m.captured) {
        let sq = m.isEnPassant() ? m.to[0] + m.from[1] : m.to;
        for (let j = defenderMoves.length - 1; j >= 0; j--) {
          if (defenderMoves[j].to === sq) sq = defenderMoves[j].from;
        }
        return sq;
      }
      if (m.color !== mover) defenderMoves.push({ from: m.from, to: m.to });
    }
    return null;
  }
  function staticFirstCaptureGain(fen, uci) {
    const c = new Chess(fen);
    const victimSq = uci.slice(2, 4);
    const victim = c.get(victimSq);
    const capturer = c.get(uci.slice(0, 2));
    if (!victim || !capturer || victim.color === capturer.color) return 0;
    if (c.attackers(victimSq, victim.color).length === 0) return PIECE_VAL[victim.type];
    return PIECE_VAL[victim.type] - PIECE_VAL[capturer.type];
  }

  // brain/engine/control.ts
  var KING_V = 100;
  function pieceVal(t) {
    return t === "k" ? KING_V : PIECE_VAL[t];
  }
  function see(target, atts, defs) {
    if (atts.length === 0) return 0;
    const [a, ...rest] = atts;
    if (a === KING_V && defs.length > 0) return 0;
    return Math.max(0, target - see(a, defs, rest));
  }
  function attackerVals(c, sq, by) {
    return c.attackers(sq, by).map((s) => pieceVal(c.get(s)?.type ?? "k")).sort((x, y) => x - y);
  }
  function bestNets(c) {
    const side = c.turn();
    const opp = side === "w" ? "b" : "w";
    const out = /* @__PURE__ */ new Map();
    for (const m of c.moves({ verbose: true })) {
      const gain = m.captured ? PIECE_VAL[m.captured] : 0;
      try {
        c.move({ from: m.from, to: m.to, promotion: m.promotion });
      } catch {
        continue;
      }
      const occ = pieceVal(m.promotion ?? m.piece);
      const net = occ === KING_V ? gain : gain - see(occ, attackerVals(c, m.to, opp), attackerVals(c, m.to, side));
      c.undo();
      const prev = out.get(m.to);
      if (prev === void 0 || net > prev) out.set(m.to, net);
    }
    return out;
  }
  function computeControl(fen) {
    const map = /* @__PURE__ */ new Map();
    let real;
    try {
      real = new Chess(fen);
    } catch {
      return map;
    }
    if (real.isGameOver() || real.inCheck()) return map;
    const parts = fen.split(" ");
    const flippedParts = [...parts];
    flippedParts[1] = parts[1] === "w" ? "b" : "w";
    flippedParts[3] = "-";
    let flipped;
    try {
      flipped = new Chess(flippedParts.join(" "));
    } catch {
      return map;
    }
    const mover = real.turn();
    const nets = {
      w: bestNets(mover === "w" ? real : flipped),
      b: bestNets(mover === "b" ? real : flipped)
    };
    const files = "abcdefgh";
    for (let f = 0; f < 8; f++) {
      for (let r = 1; r <= 8; r++) {
        const sq = files[f] + r;
        const piece = real.get(sq);
        if (piece) {
          const opp = piece.color === "w" ? "b" : "w";
          const oppNet = nets[opp].get(sq);
          if (oppNet !== void 0 && oppNet > 0) map.set(sq, opp);
        } else {
          const w = nets.w.get(sq);
          const b = nets.b.get(sq);
          const wSafe = w !== void 0 && w >= 0;
          const bSafe = b !== void 0 && b >= 0;
          if (wSafe && !bSafe) map.set(sq, "w");
          else if (bSafe && !wSafe) map.set(sq, "b");
        }
      }
    }
    return map;
  }

  // brain/practice.ts
  var KEY = "botvinnik-practice-v1";
  var INTERVAL_DAYS = [7e-3, 1, 3, 7, 21];
  function hasStorage() {
    return typeof localStorage !== "undefined";
  }
  function save(items) {
    if (hasStorage()) localStorage.setItem(KEY, JSON.stringify(items));
  }
  function itemDataFromStoredMove(move, setupUci) {
    if (!move.bestSan || !move.bestUci || !move.fenBefore || move.wcDrop <= 0) return null;
    const wcBest = Math.max(0, Math.min(100, winChance(move.evalPawns, move.mate) + move.wcDrop));
    const w = Math.max(0.01, Math.min(0.99, wcBest / 100));
    const evalBestPawns = Math.max(-15, Math.min(15, Math.log(w / (1 - w)) / 368208e-8 / 100));
    return {
      fen: move.fenBefore,
      playedSan: move.san,
      playedUci: move.uci,
      bestSan: move.bestSan,
      bestUci: move.bestUci,
      bestPv: [move.bestUci],
      setupUci: setupUci ?? enPassantSetup(move.fenBefore) ?? void 0,
      motifs: motifTags(move.fenBefore, move.bestUci, [move.bestUci], null),
      evalBestPawns,
      mateBest: null,
      wcBest,
      drop: move.wcDrop,
      depth: 22
    };
  }
  function puzzleSetupMove(item) {
    return item.setupUci ?? enPassantSetup(item.fen);
  }
  function enPassantSetup(fen) {
    const ep = fen.split(" ")[3];
    if (!ep || ep === "-" || ep.length < 2) return null;
    const file2 = ep[0];
    if (ep[1] === "6") return `${file2}7${file2}5`;
    if (ep[1] === "3") return `${file2}2${file2}4`;
    return null;
  }
  function addItem(items, data) {
    if (items.some((i) => i.fen === data.fen)) return null;
    const now = /* @__PURE__ */ new Date();
    const item = {
      ...data,
      id: data.fen,
      createdAt: now.toISOString(),
      box: 0,
      dueAt: now.toISOString(),
      // due immediately
      attempts: 0,
      correct: 0
    };
    const next = [...items, item];
    save(next);
    return next;
  }
  function removeItem(items, id) {
    const next = items.filter((i) => i.id !== id);
    save(next);
    return next;
  }
  function dueCount(items, now = Date.now()) {
    return items.filter((i) => Date.parse(i.dueAt) <= now).length;
  }
  var TACTICAL_MOTIFS = [
    "mate",
    "back-rank mate",
    "smothered mate",
    "free capture",
    "material",
    "fork",
    "pin",
    "skewer",
    "promotion"
  ];
  function puzzleDifficulty(item) {
    if (item.attempts >= 2) {
      const rate = item.correct / item.attempts;
      if (item.lastResult === "fail" && rate < 0.5) return "hard";
      if (rate >= 0.75 || item.box >= 3) return "easy";
      return "medium";
    }
    if (item.box >= 3) return "easy";
    const tactical = item.motifs?.some((m) => TACTICAL_MOTIFS.includes(m)) ?? false;
    if (item.drop >= 25 || tactical && item.drop >= 12) return "easy";
    if (item.drop < 10 && !tactical) return "hard";
    return "medium";
  }
  function masteryStats(items) {
    let mastered = 0, learning = 0, fresh = 0;
    for (const i of items) {
      if (i.attempts === 0) fresh++;
      else if (i.box >= 3) mastered++;
      else learning++;
    }
    return { mastered, learning, fresh, total: items.length };
  }
  function nextItem(items, excludeId, now = Date.now(), motif, rand2 = Math.random, easyFirst = false) {
    let pool = items.filter((i) => i.id !== excludeId);
    if (motif) pool = pool.filter((i) => i.motifs?.includes(motif));
    if (pool.length === 0) return null;
    const due = pool.filter((i) => Date.parse(i.dueAt) <= now);
    if (due.length === 0) {
      return pool.reduce((a, b) => Date.parse(a.dueAt) <= Date.parse(b.dueAt) ? a : b);
    }
    const weights = due.map((i) => {
      let w = Math.max(1, (now - Date.parse(i.dueAt)) / 6e4 + 1);
      if (easyFirst) {
        const d = puzzleDifficulty(i);
        w *= d === "easy" ? 3 : d === "hard" ? 0.5 : 1;
      }
      return w;
    });
    const total = weights.reduce((a, b) => a + b, 0);
    let r = rand2() * total;
    for (let k = 0; k < due.length; k++) {
      r -= weights[k];
      if (r <= 0) return due[k];
    }
    return due[due.length - 1];
  }
  function recordResult(items, id, pass, hinted = false) {
    const next = items.map((i) => {
      if (i.id !== id) return i;
      const box = pass ? hinted ? i.box : Math.min(i.box + 1, INTERVAL_DAYS.length - 1) : 0;
      const dueAt = new Date(Date.now() + INTERVAL_DAYS[box] * 864e5).toISOString();
      return {
        ...i,
        box,
        dueAt,
        attempts: i.attempts + 1,
        correct: i.correct + (pass ? 1 : 0),
        lastResult: pass ? "pass" : "fail"
      };
    });
    save(next);
    return next;
  }

  // brain/gameStore.ts
  var LABEL_VERSION = 1;
  function moveAccuracy(wcDrop) {
    const a = 103.1668 * Math.exp(-0.04354 * Math.max(0, wcDrop)) - 3.1669 + 1;
    return Math.max(0, Math.min(100, a));
  }
  function stdDev(xs) {
    if (xs.length === 0) return 0;
    const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
    return Math.sqrt(xs.reduce((a, b) => a + (b - mean) * (b - mean), 0) / xs.length);
  }
  function gameAccuracy(moves, color) {
    if (!moves.some((m) => m.color === color && m.label !== void 0)) return null;
    const wps = [50];
    let last = 50;
    for (const m of moves) {
      if (m.evalPawns !== null || m.mate !== null) {
        const wc = winChance(m.evalPawns, m.mate);
        last = m.color === "w" ? wc : 100 - wc;
      }
      wps.push(last);
    }
    const windowSize = Math.max(2, Math.min(8, Math.floor(wps.length / 10)));
    const windows = [];
    for (let k = 0; k < windowSize - 2; k++) windows.push(wps.slice(0, windowSize));
    for (let s = 0; s + windowSize <= wps.length; s++) windows.push(wps.slice(s, s + windowSize));
    let weightSum = 0;
    let weightedSum = 0;
    let invSum = 0;
    let n = 0;
    moves.forEach((m, i) => {
      if (m.color !== color || m.label === void 0) return;
      const acc = moveAccuracy(m.wcDrop);
      const weight = Math.max(0.5, Math.min(12, stdDev(windows[Math.min(i, windows.length - 1)] ?? wps)));
      weightedSum += acc * weight;
      weightSum += weight;
      invSum += 1 / acc;
      n++;
    });
    const weighted = weightedSum / weightSum;
    const harmonic = n / invSum;
    return Math.max(0, Math.min(100, (weighted + harmonic) / 2));
  }
  function labelCounts(moves, color) {
    const out = {};
    for (const m of moves) {
      if (m.color !== color || !m.label) continue;
      out[m.label] = (out[m.label] ?? 0) + 1;
    }
    return out;
  }

  // brain/playerElo.ts
  function playerScore(g) {
    if (g.result === "1/2-1/2") return 0.5;
    if (g.result === "1-0") return g.botColor === "b" ? 1 : 0;
    if (g.result === "0-1") return g.botColor === "w" ? 1 : 0;
    return null;
  }
  function expected(me, opp) {
    return 1 / (1 + Math.pow(10, (opp - me) / 400));
  }
  function estimatePlayerElo(gamesList) {
    const outcomes = [];
    for (const g of gamesList) {
      const p = personaById(g.botPersona);
      if (!p) continue;
      if (g.botFallback) continue;
      if ((g.botUndos ?? 0) > 0) continue;
      const score = playerScore(g);
      if (score === null) continue;
      outcomes.push({ opp: p.elo, score });
    }
    if (outcomes.length === 0) return null;
    const meanOpp = outcomes.reduce((a, o) => a + o.opp, 0) / outcomes.length;
    const fit = [...outcomes, { opp: meanOpp, score: 0.5 }];
    let best = meanOpp;
    let bestLL = -Infinity;
    for (let e = 200; e <= 2900; e += 5) {
      let ll = 0;
      for (const o of fit) {
        const p = expected(e, o.opp);
        ll += o.score * Math.log(p) + (1 - o.score) * Math.log(1 - p);
      }
      if (ll > bestLL) {
        bestLL = ll;
        best = e;
      }
    }
    const k = Math.LN10 / 400;
    let info = 0;
    for (const o of fit) {
      const p = expected(best, o.opp);
      info += k * k * p * (1 - p);
    }
    const se = info > 0 ? Math.round(1 / Math.sqrt(info)) : Infinity;
    return { elo: best, se, games: outcomes.length };
  }

  // brain/brain-entry.ts
  var BRAIN_VERSION = 1;
  function controlSquares(fen) {
    return Object.fromEntries(computeControl(fen));
  }
  return __toCommonJS(brain_entry_exports);
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
