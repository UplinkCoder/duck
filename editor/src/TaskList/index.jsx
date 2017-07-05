import Inferno from 'inferno';
import Component from 'inferno-component';
import taskManager from '../util/taskmgr';

function TaskItem({ task }) {
  return (
    <tr key={task.pid}>
      <td className="pid">{task.pid}</td>
      <td className="filename">{task.filename}</td>
      <td className="buttons">
        <button className="kill" onClick={() => taskManager.kill(task.pid)}>◼</button>
      </td>
    </tr>
  );
}

export default class TaskList extends Component {
  constructor(props) {
    super(props);
    this.state = {
      tasks: [],
    };
  }

  componentDidMount() {
    this.list(1);
  }

  componentWillUnmount() {
  }

  list(delay) {
    setTimeout(() => {
      taskManager.list((tasks) => {
        this.setState({
          tasks,
        });
        this.list();
      });
    }, delay || 250);
  }

  render() {
    const tasks = this.state.tasks.map(
      task => (<TaskItem task={task} />),
     );
    return (
      <div className="TaskList">
        <link rel="stylesheet" href="TaskList/style.less" />
        <table>
          <tr className="header">
            <th className="pid">PID</th>
            <th className="filename">Filename</th>
            <th className="buttons" />
          </tr>
          {tasks}
        </table>
      </div>
    );
  }
}
