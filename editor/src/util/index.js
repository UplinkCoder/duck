
import * as childProcess from 'child_process';

function spawn(cmd, args, callbacks) {
  args = args || [];
  callbacks = callbacks || {};

  const child = childProcess.spawn(cmd, args, {
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  if (callbacks.stdout) {
    let output = '';
    child.stdout.on('data', (buffer) => { output += buffer.toString(); });
    child.stdout.on('end', () => { callbacks.stdout(output); });
  }

  if (callbacks.stderr) {
    let output = '';
    child.stderr.on('data', (buffer) => { output += buffer.toString(); });
    child.stderr.on('end', () => { callbacks.stderr(output); });
  }

  child.on('error', (e) => { console.log('e', e); });
  return child;
}

export default {
  spawn,
};
