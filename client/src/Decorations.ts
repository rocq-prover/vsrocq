'use strict';
import * as vscode from 'vscode';
import { DidChangeConfigurationParams } from 'vscode-languageclient';

interface Decorations {
  prepared: vscode.TextEditorDecorationType;
  processing: vscode.TextEditorDecorationType;
  processed: vscode.TextEditorDecorationType
}

export let decorationsContinuous : Decorations;
export let decorationsManual : Decorations;
export let decorationsErrorAnimation : vscode.TextEditorDecorationType[];

export function initializeDecorations(context: vscode.ExtensionContext) {
  
    function create(style : vscode.DecorationRenderOptions) {
        const result = vscode.window.createTextEditorDecorationType(style);
        context.subscriptions.push(result);
        return result;
    }

    decorationsContinuous = {
        prepared: create({
            overviewRulerColor: new vscode.ThemeColor('rocq.processing.ruler'),
            overviewRulerLane: vscode.OverviewRulerLane.Right,
        }),
        processing: create({
            overviewRulerColor: new vscode.ThemeColor('rocq.prepared.ruler'),
            overviewRulerLane: vscode.OverviewRulerLane.Center,
        }),
        processed: create({
            overviewRulerColor: new vscode.ThemeColor('rocq.processed.ruler'),
            overviewRulerLane: vscode.OverviewRulerLane.Left,
        }),
    };

    decorationsManual = {
        prepared: create({
            outlineWidth: '1px',
            outlineStyle: 'solid', 
            overviewRulerColor: new vscode.ThemeColor('rocq.prepared.ruler'),
            overviewRulerLane: vscode.OverviewRulerLane.Right,
            outlineColor: new vscode.ThemeColor('rocq.prepared.outline'),
            backgroundColor: new vscode.ThemeColor('rocq.prepared.background')
        }),
        processing: create({
            overviewRulerColor: new vscode.ThemeColor('rocq.processing.ruler'), 
            overviewRulerLane: vscode.OverviewRulerLane.Center,
            backgroundColor: new vscode.ThemeColor('rocq.processing.background')
        }),
        processed: create({
            overviewRulerColor: new vscode.ThemeColor('rocq.processed.ruler'),
            overviewRulerLane: vscode.OverviewRulerLane.Left,
            backgroundColor: new vscode.ThemeColor('rocq.processed.background')
        }),
    };

    const opacities = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
    const opacityRange = opacities.concat([1]).concat(opacities.reverse());


    decorationsErrorAnimation = opacityRange.map( opacity => {
        return create({
            dark: {
                backgroundColor: `rgba(150,0,0,${opacity})`,
            },
            light: {
                backgroundColor: `rgba(150,0,0,${opacity})`,
            }
        });
    });

}

