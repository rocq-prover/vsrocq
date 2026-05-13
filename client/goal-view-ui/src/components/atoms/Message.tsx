import { FunctionComponent } from "react";

import { PpDisplay, PpString } from "pp-display";
import { MessageSeverity } from "../../types";
import classes from "./PpString.module.css";

type MessageProps = {
    message: PpString;
    severity: MessageSeverity;
    maxDepth: number;
};

const message: FunctionComponent<MessageProps> = (props) => {
    const { message, severity, maxDepth } = props;

    const classNames = [classes.Message];

    switch (severity) {
        case MessageSeverity.error:
            classNames.push(classes.Error);
            break;

        case MessageSeverity.information:
            classNames.push(classes.Info);
            break;

        case MessageSeverity.hint:
            classNames.push(classes.Hint);
            break;

        case MessageSeverity.warning:
            classNames.push(classes.Warning);
            break;
    }

    return (
        <span className={classNames.join(" ")}>
            <PpDisplay pp={message} rocqCss={classes} maxDepth={maxDepth} />
        </span>
    );
};

export default message;
