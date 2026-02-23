import 'dart:io';

import 'llama_index_retrieval.dart';

class FilesRetrieval extends LlamaIndexRetrieval {
  FilesRetrieval({
    required String name,
    required String description,
    required this.inputDir,
    BaseRetriever? retriever,
  }) : super(
         name: name,
         description: description,
         retriever: retriever ?? _InMemoryFileRetriever.fromDirectory(inputDir),
       );

  final String inputDir;
}

class _FileDocument {
  _FileDocument({required this.path, required this.text});

  final String path;
  final String text;
}

class _ScoredDocument {
  _ScoredDocument({required this.document, required this.score});

  final _FileDocument document;
  final int score;
}

class _InMemoryFileRetriever implements BaseRetriever {
  _InMemoryFileRetriever(this._documents);

  final List<_FileDocument> _documents;

  factory _InMemoryFileRetriever.fromDirectory(String inputDir) {
    final Directory root = Directory(inputDir);
    if (!root.existsSync()) {
      throw ArgumentError('input_dir does not exist: $inputDir');
    }

    final List<_FileDocument> docs = <_FileDocument>[];
    for (final FileSystemEntity entity in root.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      late final String content;
      try {
        content = entity.readAsStringSync();
      } catch (_) {
        final List<int> bytes = entity.readAsBytesSync();
        content = String.fromCharCodes(bytes);
      }
      docs.add(_FileDocument(path: entity.path, text: content));
    }
    return _InMemoryFileRetriever(docs);
  }

  @override
  List<RetrievalResult> retrieve(String query) {
    if (_documents.isEmpty) {
      return const <RetrievalResult>[];
    }
    final String normalized = query.toLowerCase();
    final List<_ScoredDocument> scored = <_ScoredDocument>[];
    for (final _FileDocument doc in _documents) {
      final String text = doc.text.toLowerCase();
      int score = 0;
      int start = 0;
      while (true) {
        final int index = text.indexOf(normalized, start);
        if (index < 0) {
          break;
        }
        score += 1;
        start = index + normalized.length;
      }
      if (score > 0) {
        scored.add(_ScoredDocument(document: doc, score: score));
      }
    }

    if (scored.isEmpty) {
      return <RetrievalResult>[RetrievalResult(text: _documents.first.text)];
    }

    scored.sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      return a.document.path.compareTo(b.document.path);
    });

    return scored
        .map((entry) => RetrievalResult(text: entry.document.text))
        .toList(growable: false);
  }
}
