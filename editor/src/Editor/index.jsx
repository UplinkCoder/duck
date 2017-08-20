import Inferno from 'inferno';
import Component from 'inferno-component';
import 'codemirror/mode/d/d.js';
import CodeMirror from './codemirror';

export default class Editor extends Component {
  constructor(props) {
    super(props);
    this.state = {
    };
  }

  componentDidMount() {
    setTimeout(() => {
      this.state.editor = CodeMirror.initialize(this.node, this.props.options);
      if (this.state.document) {
        this.state.editor.swapDoc(this.state.document);
      } else {
        this.state.document = this.state.editor.getDoc();
      }
    }, 100);
  }

  componentWillUnmount() {
  }

  render() {
    return (
      <div className="Editor">
        <link rel="stylesheet" href="Editor/style.less" />
        <div className="codemirror-container" ref={(node) => { this.node = node; }} />
      </div>
    );
  }
}
