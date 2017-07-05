import Inferno from 'inferno';
import Component from 'inferno-component';
import Editor from './Editor';
import TaskList from './TaskList';

function Window({ className, children }) {
  return (
    <div id="Window" className={`Window ${className}`}>
      { children }
    </div>
  );
}

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
            <Editor />
          </div>
        </div>
        <div className="toolbar toolbar-footer" />
      </div>
    </Window>);
  }
}
