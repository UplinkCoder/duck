import * as fs from 'fs';
import * as CodeMirror from 'codemirror';

import 'codemirror/addon/hint/show-hint';
import 'codemirror/addon/lint/lint';
import 'codemirror/mode/d/d';
import util from '../util';

function checkFile(filename, result) {
  return util.spawn('../dlib/bin/duck', ['-t', 'check', filename], {
    stderr(text) {
      result(text);
    },
  });
}

function checkText(text, result) {
  fs.writeFile('./tmp.duck', text, () => {
    checkFile('./tmp.duck', (output) => {
      result(output);
    });
  });
}

const symbols = {
  SinOsc: 'SinOsc',
  Clock: 'Clock',
  Square: 'Square',
  Triangle: 'Triangle',
  SawTooth: 'SawTooth',
  Pat: 'Pat',
  Pitch: 'Pitch',
  AR: 'AR',
  ScaleQuant: 'ScaleQuant',
  ADSR: 'ADSR',
  Delay: 'Delay',
  Echo: 'Echo',
  ADC: 'ADC',
  DAC: 'DAC',
  Osc: ['SinOsc', 'Square', 'Triangle', 'SawTooth'],
  UGen: ['Clock', 'SinOsc'],
  WhiteNoise: 'WhiteNoise',
};

const desc = {
  SinOsc: 'Sine oscillator',
  Triangle: 'Triangle oscillator',
  SawTooth: 'Saw-tooth oscillator',
  Square: 'Square wave oscillator',
  Clock: 'Clock generator',
  Pitch: 'Convert piano note number to frequency (49 => A440)',
  AR: 'Attack-release envelope',
  ADSR: 'Attack-sustain-decay-release envelope',
  Delay: 'Time delay',
  Echo: 'Echos samples with a delay',
  ADC: 'Audio input (Analog -> Digital)',
  DAC: 'Audio output (Digital -> Analog)',
  Pat: 'Pattern generator',
  WhiteNoise: 'White noise generator',
};

const help = {
  SinOsc: 'SinOsc',
};

const re = new RegExp(/[a-zA-Z][a-zA-Z0-9]*$/);
const typedef = new RegExp(/[a-z][a-zA-Z0-9_]*\s*:\s*([A-Z]?[a-zA-Z0-9_]*)$/);
const ctor = new RegExp(/([A-Z][a-zA-Z]+)(\s+[a-zA-Z]+)?\s*\([^)]*$/);

function getHint(identifier) {
  const description = desc[identifier];
  if (description) {
    return {
      text: identifier,
      displayText: `${identifier} - ${description}`,
    };
  }
  return {
    text: identifier,
    displayText: identifier,
  };
}

function maybeAdd(found, str, text, value) {
  if (text.indexOf(str) === 0) {
    if (typeof value === 'string') {
      found.push(getHint(value));
    } else {
      for (let i = 0; i < value.length; ++i) {
        found.push(getHint(value[i]));
      }
    }
  }
}

function findCompletions(text) {
  if (text === null || text === undefined) { return []; }

  const completions = [];
  Object.keys(symbols).forEach((key) => {
    const keys = symbols[key];
    if (key.indexOf(text) === 0) {
      if (typeof keys === 'string') {
        completions.push(getHint(keys));
      } else {
        for (let i = 0; i < keys.length; ++i) {
          completions.push(getHint(keys[i]));
        }
      }
    }
  });
  return completions;
}

CodeMirror.registerHelper('hint', 'duck', (editor/*, options*/) => {
  const cur = editor.getCursor();
  const cursor = cur;
  const found = [];
  let start;


  const line = editor.getLine(cur.line).slice(0, cur.ch);
  const mtypedef = line.match(typedef);
  if (mtypedef) {
    return {
      list: findCompletions(mtypedef[1]),
      from: CodeMirror.Pos(cur.line, cursor.ch - mtypedef[1].length),
      to: cur,
    };
  }

  const ctorm = line.match(ctor);
  if (ctorm) {
    return {
      list: [{
        //text: 'fds',
        hint() {},
        displayText: help[ctorm[1]],
      }],
      from: cursor,
      to: cur,
    };
  }

  if (line[cursor.ch - 1] === ' ' && line[cursor.ch - 1] === '\t') {
    return {};
  }

  const match = line.match(re);
    //console.log(line, match)
  const str = match && match[0];
  if (str && str.length > 0) {
    start = cur.ch - str.length;
  } else {
    start = cur.ch;
  }

  return {
    list: findCompletions(str),
    from: CodeMirror.Pos(cur.line, start),
    to: cur,
  };
});


function parseErrors(text) {
  text = text || '';
  const found = [];
  const errors = text.split('\n');
  for (let i = 0; i < errors.length; ++i) {
    let m = errors[i].match(/^[.a-zA-Z0-9_\-/]*\((\d+):(\d+)-(?:(\d+):)?(\d+)\):\s+(.*)/);
    if (!m) {
      m = errors[i].match(/^[.a-zA-Z0-9_\-/]*\((\d+):(\d+)\):\s+(.*)/);
      if (m) {
        m[5] = m[3];
        m[3] = m[1];
        m[4] = m[2];
      }
    }

    if (m) {
      found.push({
        from: CodeMirror.Pos(+m[1] - 1, m[2] - 1),
        to: CodeMirror.Pos(+(m[3] || m[1]) - 1, m[4]),
        message: m[5],
      });
    }
  }
  return found;
}

function validate(callback) {
  return (code, updateLinting, options, cm) => {
    code = `${code}\n`;
    if (code.trim() === '') {
      updateLinting(cm, []);
      callback([]);
    }

    checkText(code, (output) => {
      console.log(output);
      const errors = parseErrors(output);
      cm.operation(() => {
        updateLinting(cm, errors);
      });
      callback(errors);
    });
  };
}

export default {
  validate,
};
