import * as fs from 'fs';
import Inferno from 'inferno';
import Component from 'inferno-component';
import Editor from './Editor';
import TaskList from './TaskList';
import util from './util';
import taskManager from './util/taskmgr';

function Window({ className, children }) {
  return (
    <div id="Window" className={`Window ${className}`}>
      { children }
    </div>
  );
}

const editorOptions = {
  validateCode(text, callback) {
    fs.writeFile('./tmp.duck', text, () =>
      util.spawn('../bin/duck', ['-t', 'check', './tmp.duck'], {
        stderr(text) {
          callback(text);
        }
      }),
    );
  },

  executeCode(code, callback) {
    taskManager.execute('temp', code, callback);
  }
};

export default class App extends Component {
  render() {
    return (<Window className="layout-right">
      {/*}<div className="WindowTitleBar toolbar toolbar-header">
        <div className="WindowTitle title"> Duck pond </div>
      </div>*/}
      <div id="Contents" className="">
        {/*<SidebarNav className="left-sidebar" nav="" />*/}
        <div className="right-panel">
          <TaskList />
        </div>
        <div className="center-panel">
          <div id="editor-panel" className="editor-panel">
            <Editor options={editorOptions} />
          </div>
        </div>
        <div className="toolbar toolbar-footer" />
      </div>
    </Window>);
  }
}
