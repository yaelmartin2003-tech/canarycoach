import 'package:flutter/material.dart';

import '../../data/user_store.dart';
import '../../theme/app_theme.dart';

class QuestionnaireEditorResult {
  const QuestionnaireEditorResult({
    required this.questions,
    required this.answers,
  });

  final List<QuestionnaireQuestion> questions;
  final Map<String, String> answers;
}

Future<QuestionnaireEditorResult?> showQuestionnaireEditorDialog(
  BuildContext context, {
  required String title,
  required List<QuestionnaireQuestion> initialQuestions,
  required Map<String, String> initialAnswers,
  bool allowQuestionEditing = false,
  bool dismissible = true,
}) {
  return showDialog<QuestionnaireEditorResult>(
    context: context,
    barrierDismissible: dismissible,
    builder: (_) => _QuestionnaireEditorDialog(
      title: title,
      initialQuestions: initialQuestions,
      initialAnswers: initialAnswers,
      allowQuestionEditing: allowQuestionEditing,
      dismissible: dismissible,
    ),
  );
}

class _QuestionnaireEditorDialog extends StatefulWidget {
  const _QuestionnaireEditorDialog({
    required this.title,
    required this.initialQuestions,
    required this.initialAnswers,
    required this.allowQuestionEditing,
    required this.dismissible,
  });

  final String title;
  final List<QuestionnaireQuestion> initialQuestions;
  final Map<String, String> initialAnswers;
  final bool allowQuestionEditing;
  final bool dismissible;

  @override
  State<_QuestionnaireEditorDialog> createState() =>
      _QuestionnaireEditorDialogState();
}

class _QuestionnaireEditorDialogState extends State<_QuestionnaireEditorDialog> {
  late List<QuestionnaireQuestion> _questions;
  final Map<String, TextEditingController> _questionCtrls = {};
  final Map<String, TextEditingController> _answerCtrls = {};

  @override
  void initState() {
    super.initState();
    _questions = widget.initialQuestions
        .map((q) => QuestionnaireQuestion(id: q.id, text: q.text))
        .toList();
    for (final q in _questions) {
      _questionCtrls[q.id] = TextEditingController(text: q.text);
      _answerCtrls[q.id] = TextEditingController(
        text: widget.initialAnswers[q.id] ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _questionCtrls.values) {
      c.dispose();
    }
    for (final c in _answerCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addQuestion() {
    final id = 'q-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _questions = [
        ..._questions,
        QuestionnaireQuestion(id: id, text: ''),
      ];
      _questionCtrls[id] = TextEditingController();
      _answerCtrls[id] = TextEditingController();
    });
  }

  void _removeQuestion(String id) {
    setState(() {
      _questions = _questions.where((q) => q.id != id).toList();
      _questionCtrls.remove(id)?.dispose();
      _answerCtrls.remove(id)?.dispose();
    });
  }

  void _save() {
    final nextQuestions = <QuestionnaireQuestion>[];
    final nextAnswers = <String, String>{};

    for (final q in _questions) {
      final text = (widget.allowQuestionEditing
              ? _questionCtrls[q.id]?.text
              : q.text)
          ?.trim() ??
          '';
      if (text.isEmpty) continue;
      nextQuestions.add(QuestionnaireQuestion(id: q.id, text: text));
      final answer = _answerCtrls[q.id]?.text.trim() ?? '';
      if (answer.isNotEmpty) {
        nextAnswers[q.id] = answer;
      }
    }

    if (nextQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes tener al menos una pregunta.')),
      );
      return;
    }

    Navigator.of(context).pop(
      QuestionnaireEditorResult(
        questions: nextQuestions,
        answers: nextAnswers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final surface = AppTheme.modalSurfaceFor(context);
    final muted = onSurface.withValues(alpha: 0.65);

    return AlertDialog(
      backgroundColor: surface,
      insetPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppTheme.modalBorderFor(context), width: 1.2),
      ),
      titlePadding: EdgeInsets.fromLTRB(16, 14, 16, 8),
      contentPadding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      actionsPadding: EdgeInsets.fromLTRB(10, 0, 10, 10),
      title: Row(
        children: [
          Icon(Icons.quiz_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (var i = 0; i < _questions.length; i++)
                Container(
                  margin: EdgeInsets.only(bottom: i == _questions.length - 1 ? 0 : 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${i + 1}.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: widget.allowQuestionEditing
                                ? TextField(
                                    controller: _questionCtrls[_questions[i].id],
                                    style: TextStyle(color: onSurface),
                                    decoration: InputDecoration(
                                      hintText: 'Escribe la pregunta',
                                      hintStyle: TextStyle(color: muted),
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                  )
                                : Text(
                                    _questions[i].text,
                                    style: TextStyle(
                                      color: onSurface,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                          ),
                          if (widget.allowQuestionEditing)
                            IconButton(
                              onPressed: () => _removeQuestion(_questions[i].id),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFFE57373),
                                size: 18,
                              ),
                              splashRadius: 18,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _answerCtrls[_questions[i].id],
                        minLines: 2,
                        maxLines: 4,
                        style: TextStyle(color: onSurface, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Respuesta',
                          hintStyle: TextStyle(color: muted),
                          filled: true,
                          fillColor: onSurface.withValues(alpha: 0.06),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: theme.dividerColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.allowQuestionEditing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addQuestion,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Añadir pregunta'),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.dismissible)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancelar',
              style: TextStyle(color: muted),
            ),
          ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
