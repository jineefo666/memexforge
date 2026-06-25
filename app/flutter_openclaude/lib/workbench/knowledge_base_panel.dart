import 'package:flutter/material.dart';

import 'workbench_models.dart';

typedef MemoryFactDeletedHandler = void Function(String source, String id);
typedef MemoryFactDisabledChangedHandler =
    void Function(String source, String id, bool disabled);

class KnowledgeBasePanel extends StatefulWidget {
  const KnowledgeBasePanel({
    super.key,
    required this.state,
    this.onIndexRequested,
    this.onRetrievalEvaluationRequested,
    this.onMemoryFactsRefresh,
    this.onMemoryFactDeleted,
    this.onMemoryFactDisabledChanged,
    this.onMemoryFactEdited,
  });

  final WorkbenchState state;
  final ValueChanged<KnowledgeIndexRequest>? onIndexRequested;
  final VoidCallback? onRetrievalEvaluationRequested;
  final VoidCallback? onMemoryFactsRefresh;
  final MemoryFactDeletedHandler? onMemoryFactDeleted;
  final MemoryFactDisabledChangedHandler? onMemoryFactDisabledChanged;
  final ValueChanged<MemoryFactEditRequest>? onMemoryFactEdited;

  @override
  State<KnowledgeBasePanel> createState() => _KnowledgeBasePanelState();
}

class _KnowledgeBasePanelState extends State<KnowledgeBasePanel> {
  late final TextEditingController _pathController;
  late KnowledgeIndexTarget _target;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(
      text: widget.state.knowledgeIndex.path,
    );
    _target = widget.state.knowledgeIndex.target;
  }

  @override
  void didUpdateWidget(covariant KnowledgeBasePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.knowledgeIndex.path !=
            widget.state.knowledgeIndex.path &&
        _pathController.text.trim().isEmpty) {
      _pathController.text = widget.state.knowledgeIndex.path;
    }
    _target = widget.state.knowledgeIndex.target;
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final indexState = widget.state.knowledgeIndex;
    final isIndexing = indexState.status == KnowledgeIndexStatus.indexing;

    return Container(
      key: const ValueKey('knowledge-panel'),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Icon(Icons.folder_copy_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Knowledge', style: theme.textTheme.titleLarge),
                ),
                _StatusPill(status: indexState.status),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 18,
              runSpacing: 18,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<KnowledgeIndexTarget>(
                  segments: const [
                    ButtonSegment(
                      value: KnowledgeIndexTarget.directory,
                      icon: Icon(Icons.folder_outlined),
                      label: Text('Directory'),
                    ),
                    ButtonSegment(
                      value: KnowledgeIndexTarget.file,
                      icon: Icon(Icons.description_outlined),
                      label: Text('File'),
                    ),
                  ],
                  selected: {_target},
                  onSelectionChanged: isIndexing
                      ? null
                      : (selection) {
                          setState(() => _target = selection.single);
                        },
                ),
                SizedBox(
                  width: 520,
                  child: TextField(
                    key: const ValueKey('knowledge-path-input'),
                    controller: _pathController,
                    enabled: !isIndexing,
                    decoration: const InputDecoration(
                      labelText: 'Path',
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('knowledge-index-button'),
                  onPressed: isIndexing ? null : _submit,
                  icon: isIndexing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_outlined),
                  label: Text(isIndexing ? 'Indexing' : 'Index'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _IndexSummary(state: indexState),
            const SizedBox(height: 18),
            _SourcePathList(sourcePaths: indexState.sourcePaths),
            const SizedBox(height: 18),
            _RetrievalEvaluationPanel(
              state: widget.state.retrievalEvaluation,
              onRun: widget.onRetrievalEvaluationRequested,
            ),
            const SizedBox(height: 18),
            _MemoryManager(
              facts: widget.state.memoryFacts,
              onRefresh: widget.onMemoryFactsRefresh,
              onDeleted: widget.onMemoryFactDeleted,
              onDisabledChanged: widget.onMemoryFactDisabledChanged,
              onEdited: widget.onMemoryFactEdited,
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) return;
    widget.onIndexRequested?.call(
      KnowledgeIndexRequest(target: _target, path: path),
    );
  }
}

class _RetrievalEvaluationPanel extends StatelessWidget {
  const _RetrievalEvaluationPanel({required this.state, this.onRun});

  final RetrievalEvaluationState state;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = state.report;
    final isRunning = state.status == RetrievalEvaluationStatus.running;
    return DecoratedBox(
      key: const ValueKey('retrieval-evaluation-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Evaluation', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('retrieval-evaluation-run-button'),
                  onPressed: isRunning ? null : onRun,
                  icon: isRunning
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.analytics_outlined),
                  label: Text(isRunning ? 'Running' : 'Run'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.errorMessage != null)
              Text(
                state.errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              )
            else if (report == null)
              Text('No evaluation report', style: theme.textTheme.bodyMedium)
            else ...[
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Metric(label: 'Hit Rate', value: _percent(report.hitRate)),
                  _Metric(label: 'MRR', value: report.mrr.toStringAsFixed(2)),
                  _Metric(
                    label: 'Precision@${report.k}',
                    value: _percent(report.precisionAtK),
                  ),
                ],
              ),
              if (report.sourceShare.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Source Share', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                for (final entry in report.sourceShare.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SourceShareRow(
                      source: entry.key,
                      share: entry.value,
                    ),
                  ),
              ],
              if (report.cases.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Cases', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                for (final result in report.cases.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EvaluationCaseRow(result: result),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _percent(double value) {
    return '${(value * 100).round()}%';
  }
}

class _SourceShareRow extends StatelessWidget {
  const _SourceShareRow({required this.source, required this.share});

  final String source;
  final double share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 90, child: Text(source)),
        Expanded(child: LinearProgressIndicator(value: share.clamp(0, 1))),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            '${(share * 100).round()}%',
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium,
          ),
        ),
      ],
    );
  }
}

class _EvaluationCaseRow extends StatelessWidget {
  const _EvaluationCaseRow({required this.result});

  final RetrievalEvaluationCaseResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          result.hit ? Icons.check_circle_outline : Icons.highlight_off,
          size: 18,
          color: result.hit
              ? theme.colorScheme.primary
              : theme.colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            result.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          result.firstRelevantRank == null
              ? 'miss'
              : 'rank ${result.firstRelevantRank}',
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _MemoryManager extends StatelessWidget {
  const _MemoryManager({
    required this.facts,
    this.onRefresh,
    this.onDeleted,
    this.onDisabledChanged,
    this.onEdited,
  });

  final List<MemoryFact> facts;
  final VoidCallback? onRefresh;
  final MemoryFactDeletedHandler? onDeleted;
  final MemoryFactDisabledChangedHandler? onDisabledChanged;
  final ValueChanged<MemoryFactEditRequest>? onEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Memory', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh memory',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (facts.isEmpty)
              Text('No memory facts', style: theme.textTheme.bodyMedium)
            else
              for (final fact in facts) ...[
                _MemoryFactTile(
                  fact: fact,
                  onDeleted: onDeleted,
                  onDisabledChanged: onDisabledChanged,
                  onEdited: onEdited,
                ),
                if (fact != facts.last) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _MemoryFactTile extends StatelessWidget {
  const _MemoryFactTile({
    required this.fact,
    this.onDeleted,
    this.onDisabledChanged,
    this.onEdited,
  });

  final MemoryFact fact;
  final MemoryFactDeletedHandler? onDeleted;
  final MemoryFactDisabledChangedHandler? onDisabledChanged;
  final ValueChanged<MemoryFactEditRequest>? onEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      key: ValueKey('memory-fact-${fact.source}-${fact.id}'),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MemorySourcePill(label: fact.sourceLabel),
                      if (fact.disabled)
                        const _MemorySourcePill(label: 'Disabled'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(fact.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    fact.content,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: fact.disabled ? 'Enable memory' : 'Disable memory',
                  onPressed: () => onDisabledChanged?.call(
                    fact.source,
                    fact.id,
                    !fact.disabled,
                  ),
                  icon: Icon(
                    fact.disabled
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Edit memory',
                  onPressed: () => _showEditDialog(context),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete memory',
                  onPressed: () => onDeleted?.call(fact.source, fact.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context) async {
    final result = await showDialog<MemoryFactEditRequest>(
      context: context,
      builder: (context) => _MemoryEditDialog(fact: fact),
    );
    if (result != null) onEdited?.call(result);
  }
}

class _MemoryEditDialog extends StatefulWidget {
  const _MemoryEditDialog({required this.fact});

  final MemoryFact fact;

  @override
  State<_MemoryEditDialog> createState() => _MemoryEditDialogState();
}

class _MemoryEditDialogState extends State<_MemoryEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.fact.title);
    _contentController = TextEditingController(text: widget.fact.content);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit memory'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('memory-edit-title-input'),
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('memory-edit-content-input'),
              controller: _contentController,
              decoration: const InputDecoration(labelText: 'Content'),
              minLines: 3,
              maxLines: 6,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) return;
    Navigator.of(context).pop(
      MemoryFactEditRequest(
        source: widget.fact.source,
        id: widget.fact.id,
        title: title,
        content: content,
      ),
    );
  }
}

class _MemorySourcePill extends StatelessWidget {
  const _MemorySourcePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final KnowledgeIndexStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      KnowledgeIndexStatus.idle => (
        'Idle',
        colorScheme.surfaceContainerHighest,
      ),
      KnowledgeIndexStatus.indexing => (
        'Indexing',
        colorScheme.primaryContainer,
      ),
      KnowledgeIndexStatus.completed => (
        'Ready',
        colorScheme.tertiaryContainer,
      ),
      KnowledgeIndexStatus.failed => ('Failed', colorScheme.errorContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _IndexSummary extends StatelessWidget {
  const _IndexSummary({required this.state});

  final KnowledgeIndexState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = state.errorMessage;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Metric(label: 'Nodes', value: state.indexedNodes.toString()),
                _Metric(
                  label: 'Sources',
                  value: state.sourcePaths.length.toString(),
                ),
                _Metric(label: 'Target', value: _targetLabel(state.target)),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  String _targetLabel(KnowledgeIndexTarget target) {
    return switch (target) {
      KnowledgeIndexTarget.file => 'File',
      KnowledgeIndexTarget.directory => 'Directory',
    };
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _SourcePathList extends StatelessWidget {
  const _SourcePathList({required this.sourcePaths});

  final List<String> sourcePaths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Indexed Sources', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (sourcePaths.isEmpty)
              Text('No sources indexed', style: theme.textTheme.bodyMedium)
            else
              for (final sourcePath in sourcePaths.take(24))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(sourcePath)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
