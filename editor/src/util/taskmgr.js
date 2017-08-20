import * as fs from 'fs';
import util from '../util';

class TaskManager {
  constructor() {
    this.queue = [];
    this.start();
  }

  executeNext() {
    const command = this.queue[0];
    if (!command) { return; }

    this.waiter = (result) => {
      if (command.callback) {
        command.callback(result);
      }

      // Remove from queue
      this.queue.splice(0, 1);
      this.executeNext();
    };
    command.fn();
  }

  enqueue(fn, callback) {
    this.queue.push({
      fn,
      callback,
    });
    if (this.queue.length === 1) {
      this.executeNext();
    }
  }

  send(command, callback) {
    this.enqueue(() => {
      this.process.stdin.write(command);
      //console.log(`Sent: ${command}`);
    }, callback);
  }

  start() {
    this.process = util.spawn('../bin/iduck');

    let output = '';
    this.process.stderr.on('data', (buffer) => {
      //console.log(`Received error data: [${buffer.toString()}]`);
    });
    this.process.stdout.on('data', (buffer) => {
      //console.log(`Received data: [${buffer.toString()}]`);
      if (buffer.length > 0) {
        output += buffer.toString();
      }
      const chevronIndex = output.indexOf('>');

      if (chevronIndex < 0) {
        return;
      }
      const result = output.slice(0, chevronIndex);
      output = output.slice(chevronIndex + 1);

      if (this.waiter) {
        const waiter = this.waiter;
        this.waiter = null;
        waiter(result);
      }
    });
    this.enqueue(() => {}, (result) => {
    });
  }

  kill(pid, callback) {
    this.send(`stop ${pid}\n`, callback);
  }

  list(callback) {
    this.send('list\n', (string) => {
      const list = string.split('\n').slice(0, -1);
      const all = [];
      for (let i = 0; i < list.length; i++) {
        const parts = list[i].split(/\s*:\s*/);
        if (parts.length === 2) {
          all.push({
            pid: parts[0],
            filename: parts[1],
          });
        }
      }
      callback(all);
    });
  }

  execute(filename, text, callback) {
    fs.writeFile(`./${filename}`, text, () => {
      this.send(`start ${filename}\n`, callback);
        //var line = string.split("\n")[0]
        //var lines = [];
        //var line = lines.splice(0, 1)[0];
        //var parts = line.split(/\s*:\s*/
    });
  }
}

const instance = new TaskManager();
export default instance;
