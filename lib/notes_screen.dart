import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:calendar_app/database_helper.dart';
import 'package:calendar_app/notification_helper.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:hand_signature/signature.dart';
import 'package:hand_signature/svg_parser.dart';

import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:share_plus/share_plus.dart';

class Note {
  final int id;
  final String content;
  final DateTime date;
  final bool isCompleted;
  final bool isHandwritten;
  final List<String> tags;
  final String? audioPath;
  final bool isFavorite;

  Note({
    required this.id,
    required this.content,
    required this.date,
    required this.isCompleted,
    required this.isHandwritten,
    required this.tags,
    this.audioPath,
    required this.isFavorite,
  });
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({Key? key}) : super(key: key);

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late TextEditingController _searchController;
  List<Note> _allNotes = [];
  List<Note> _filteredNotes = [];
  String _sortCriteria = 'date';
  bool _sortAscending = true;
  bool _gridView = false;
  String? _selectedTag;
  DateTime? _startDateFilter;
  DateTime? _endDateFilter;
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const List<String> _predefinedTags = ['Urgente', 'Idea', 'Tarea', 'Predicación', 'Reunión'];
  String _searchHighlight = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final notes = await DatabaseHelper.instance.getAllNotes();
    setState(() {
      _allNotes = notes.map((note) => Note(
        id: note['id'],
        content: note['content'],
        date: DateTime.parse(note['date']),
        isCompleted: note['isCompleted'] == 1,
        isHandwritten: note['isHandwritten'] == 1,
        tags: List<String>.from(jsonDecode(note['tags'] ?? '[]')),
        audioPath: note['audioPath'],
        isFavorite: note['isFavorite'] == 1,
      )).toList();
      _applyFiltersAndSort();
    });
  }

  void _applyFiltersAndSort() {
    _filteredNotes = List.from(_allNotes);

    // Filtro por texto
    if (_searchController.text.isNotEmpty) {
      _searchHighlight = _searchController.text.toLowerCase();
      _filteredNotes = _filteredNotes.where((note) {
        final content = _parseContent(note.content, note.isHandwritten);
        return content.toLowerCase().contains(_searchHighlight);
      }).toList();
    } else {
      _searchHighlight = '';
    }

    // Filtro por etiqueta
    if (_selectedTag != null) {
      _filteredNotes = _filteredNotes.where((note) => note.tags.contains(_selectedTag)).toList();
    }

    // Filtro por fechas
    if (_startDateFilter != null) {
      _filteredNotes = _filteredNotes.where(
        (note) => note.date.isAfter(_startDateFilter!.subtract(const Duration(days: 1))),
      ).toList();
    }
    if (_endDateFilter != null) {
      _filteredNotes = _filteredNotes.where(
        (note) => note.date.isBefore(_endDateFilter!.add(const Duration(days: 1))),
      ).toList();
    }

    // Ordenamiento
    _filteredNotes.sort((a, b) {
      int comparison;
      switch (_sortCriteria) {
        case 'date':
          comparison = a.date.compareTo(b.date);
          break;
        case 'content':
          comparison = _parseContent(a.content, a.isHandwritten)
              .compareTo(_parseContent(b.content, b.isHandwritten));
          break;
        case 'completed':
          comparison = (a.isCompleted ? 1 : 0).compareTo(b.isCompleted ? 1 : 0);
          break;
        default:
          comparison = 0;
      }
      return _sortAscending ? comparison : -comparison;
    });

    setState(() {});
  }

  String _parseContent(String content, bool isHandwritten) {
    if (isHandwritten) return 'Nota manuscrita';
    try {
      final delta = jsonDecode(content) as List;
      return delta.map((op) => op['insert']?.toString() ?? '').join();
    } catch (e) {
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notas', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _searchController.clear();
                _applyFiltersAndSort();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportAllNotes,
          ),
          IconButton(
            icon: const Icon(Icons.add_comment),
            onPressed: _addQuickNote,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildNotesView()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNote,
        child: const Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar notas...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                  ),
                  onChanged: (value) => _applyFiltersAndSort(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_gridView ? Icons.list : Icons.grid_view),
                onPressed: () => setState(() => _gridView = !_gridView),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _selectedTag,
                  hint: const Text('Etiqueta'),
                  items: _predefinedTags
                      .map((tag) => DropdownMenuItem(value: tag, child: Text(tag)))
                      .toList()
                    ..add(const DropdownMenuItem(value: null, child: Text('Todas'))),
                  onChanged: (value) {
                    setState(() {
                      _selectedTag = value;
                      _applyFiltersAndSort();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _showDateRangePicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Rango de Fechas'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesView() {
    if (_filteredNotes.isEmpty) {
      return const Center(child: Text('No hay notas disponibles.'));
    }

    return _gridView
        ? GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
            ),
            itemCount: _filteredNotes.length,
            itemBuilder: (context, index) => _buildNoteCard(_filteredNotes[index]),
          )
        : ListView.builder(
            itemCount: _filteredNotes.length,
            itemBuilder: (context, index) => _buildNoteCard(_filteredNotes[index]),
          );
  }

  Widget _buildNoteCard(Note note) {
    return Dismissible(
      key: Key(note.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) async {
        await DatabaseHelper.instance.deleteNote(note.id);
        if (note.audioPath != null) {
          await File(note.audioPath!).delete();
        }
        _loadNotes();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nota eliminada'),
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () async {
                await DatabaseHelper.instance.insertNote({
                  'date': note.date.toIso8601String(),
                  'content': note.content,
                  'isCompleted': note.isCompleted ? 1 : 0,
                  'isHandwritten': note.isHandwritten ? 1 : 0,
                  'tags': jsonEncode(note.tags),
                  'audioPath': note.audioPath,
                  'isFavorite': note.isFavorite ? 1 : 0,
                });
                _loadNotes();
              },
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: note.isCompleted
            ? Theme.of(context).cardColor.withOpacity(0.7)
            : Theme.of(context).cardColor,
        child: ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: note.isCompleted,
                onChanged: (value) async {
                  await DatabaseHelper.instance.updateNote({
                    'id': note.id,
                    'date': note.date.toIso8601String(),
                    'content': note.content,
                    'isCompleted': value! ? 1 : 0,
                    'isHandwritten': note.isHandwritten ? 1 : 0,
                    'tags': jsonEncode(note.tags),
                    'audioPath': note.audioPath,
                    'isFavorite': note.isFavorite ? 1 : 0,
                  });
                  _loadNotes();
                },
                activeColor: Theme.of(context).primaryColor,
              ),
              if (note.isFavorite) const Icon(Icons.star, color: Colors.yellow, size: 20),
            ],
          ),
          title: note.isHandwritten
              ? SizedBox(
                  height: 50,
                  child: HandSignature(
                    control: HandSignatureControl()
                      ..draw(SvgParser().parse(note.content)),
                    color: Colors.black,
                    width: 2.0,
                  ),
                )
              : RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: _highlightSearchText(_parseContent(note.content, false)),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('dd/MM/yyyy HH:mm').format(note.date),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 12),
              ),
              if (note.tags.isNotEmpty)
                Wrap(
                  spacing: 4.0,
                  children: note.tags.map((tag) {
                    return Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 10)),
                      padding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              if (note.audioPath != null)
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  onPressed: () => _playAudio(note.audioPath!),
                ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editNote(note),
          ),
          onTap: () => _showNoteDetails(note),
        ),
      ),
    );
  }

  List<TextSpan> _highlightSearchText(String text) {
    if (_searchHighlight.isEmpty) {
      return [TextSpan(text: text)];
    }
    final spans = <TextSpan>[];
    int start = 0;
    while (start < text.length) {
      final index = text.toLowerCase().indexOf(_searchHighlight, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + _searchHighlight.length),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + _searchHighlight.length;
    }
    return spans;
  }

  void _addQuickNote() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota Rápida'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Escribe una nota rápida...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.insertNote({
        'date': DateTime.now().toIso8601String(),
        'content': jsonEncode([{'insert': result + '\n'}]),
        'isCompleted': 0,
        'isHandwritten': 0,
        'tags': jsonEncode([]),
        'audioPath': null,
        'isFavorite': 0,
      });
      _loadNotes();
    }
  }

  void _addNote() async {
    final quillController = quill.QuillController.basic();
    final handSignatureControl = HandSignatureControl();
    bool handwritingMode = false;
    List<String> tags = [];
    String? audioPath;
    String template = 'none';
    DateTime? reminderTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _buildNoteEditorDialog(
        title: 'Nueva Nota',
        quillController: quillController,
        handSignatureControl: handSignatureControl,
        initialHandwritingMode: handwritingMode,
        initialTags: tags,
        initialAudioPath: audioPath,
        initialTemplate: template,
        onModeChange: (mode) => handwritingMode = mode,
        onTagsChange: (newTags) => tags = newTags,
        onAudioChange: (path) => audioPath = path,
        onTemplateChange: (temp) => template = temp,
        onReminderChange: (time) => reminderTime = time,
      ),
    );

    if (result != null) {
      final noteId = await DatabaseHelper.instance.insertNote({
        'date': result['date'].toIso8601String(),
        'content': result['content'],
        'isCompleted': 0,
        'isHandwritten': result['isHandwritten'] ? 1 : 0,
        'tags': jsonEncode(result['tags']),
        'audioPath': result['audioPath'],
        'isFavorite': 0,
      });
      if (reminderTime != null) {
        await NotificationHelper.scheduleNotification(
          id: noteId,
          title: 'Recordatorio de Nota',
          body: handwritingMode ? 'Nota manuscrita' : _parseContent(result['content'], false),
          scheduledTime: reminderTime,
        );
      }
      _loadNotes();
    }
  }

  void _editNote(Note note) async {
    final quillController = quill.QuillController(
      document: note.isHandwritten
          ? quill.Document()
          : quill.Document.fromJson(jsonDecode(note.content)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final handSignatureControl = HandSignatureControl();
    if (note.isHandwritten) {
      final svgData = note.content;
      if (svgData.isNotEmpty) {
        handSignatureControl.draw(SvgParser().parse(svgData));
      }
    }
    bool handwritingMode = note.isHandwritten;
    List<String> tags = List.from(note.tags);
    String? audioPath = note.audioPath;
    bool isFavorite = note.isFavorite;
    DateTime? reminderTime;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _buildNoteEditorDialog(
        title: 'Editar Nota',
        quillController: quillController,
        handSignatureControl: handSignatureControl,
        initialHandwritingMode: handwritingMode,
        initialTags: tags,
        initialAudioPath: audioPath,
        initialTemplate: 'none',
        date: note.date,
        onModeChange: (mode) => handwritingMode = mode,
        onTagsChange: (newTags) => tags = newTags,
        onAudioChange: (path) => audioPath = path,
        onFavoriteChange: (value) => isFavorite = value,
        isFavorite: isFavorite,
        onReminderChange: (time) => reminderTime = time,
      ),
    );

    if (result != null) {
      await DatabaseHelper.instance.updateNote({
        'id': note.id,
        'date': result['date'].toIso8601String(),
        'content': result['content'],
        'isCompleted': note.isCompleted ? 1 : 0,
        'isHandwritten': result['isHandwritten'] ? 1 : 0,
        'tags': jsonEncode(result['tags']),
        'audioPath': result['audioPath'],
        'isFavorite': isFavorite ? 1 : 0,
      });
      // Si el audio cambió, eliminamos el antiguo
      if (audioPath != note.audioPath && note.audioPath != null) {
        await File(note.audioPath!).delete();
      }
      // Reprogramar recordatorio si lo hay
      if (reminderTime != null) {
        await NotificationHelper.cancelNotification(note.id);
        await NotificationHelper.scheduleNotification(
          id: note.id,
          title: 'Recordatorio de Nota',
          body: handwritingMode ? 'Nota manuscrita' : _parseContent(result['content'], false),
          scheduledTime: reminderTime,
        );
      }
      _loadNotes();
    }
  }

  Widget _buildNoteEditorDialog({
    required String title,
    required quill.QuillController quillController,
    required HandSignatureControl handSignatureControl,
    required bool initialHandwritingMode,
    required List<String> initialTags,
    required String? initialAudioPath,
    required String initialTemplate,
    DateTime? date,
    required ValueChanged<bool> onModeChange,
    required ValueChanged<List<String>> onTagsChange,
    required ValueChanged<String?> onAudioChange,
    ValueChanged<String>? onTemplateChange,
    bool isFavorite = false,
    ValueChanged<bool>? onFavoriteChange,
    ValueChanged<DateTime?>? onReminderChange,
  }) {
    bool handwritingMode = initialHandwritingMode;
    List<String> tags = List.from(initialTags);
    String? audioPath = initialAudioPath;
    String template = initialTemplate;
    DateTime selectedDate = date ?? DateTime.now();
    Color penColor = Colors.black;
    double penWidth = 2.0;
    bool eraserMode = false;
    DateTime? reminderTime;

    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title),
            if (handwritingMode)
              PopupMenuButton<String>(
                onSelected: (value) {
                  setState(() {
                    switch (value) {
                      case 'black':
                        penColor = Colors.black;
                        eraserMode = false;
                        break;
                      case 'blue':
                        penColor = Colors.blue;
                        eraserMode = false;
                        break;
                      case 'red':
                        penColor = Colors.red;
                        eraserMode = false;
                        break;
                      case 'width_1':
                        penWidth = 1.0;
                        eraserMode = false;
                        break;
                      case 'width_2':
                        penWidth = 2.0;
                        eraserMode = false;
                        break;
                      case 'width_4':
                        penWidth = 4.0;
                        eraserMode = false;
                        break;
                      case 'eraser':
                        eraserMode = true;
                        break;
                      case 'clear':
                        handSignatureControl.clear();
                        break;
                    }
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'black', child: Text('Negro')),
                  const PopupMenuItem(value: 'blue', child: Text('Azul')),
                  const PopupMenuItem(value: 'red', child: Text('Rojo')),
                  const PopupMenuItem(value: 'width_1', child: Text('Grosor 1')),
                  const PopupMenuItem(value: 'width_2', child: Text('Grosor 2')),
                  const PopupMenuItem(value: 'width_4', child: Text('Grosor 4')),
                  const PopupMenuItem(value: 'eraser', child: Text('Borrador')),
                  const PopupMenuItem(value: 'clear', child: Text('Limpiar')),
                ],
                icon: const Icon(Icons.brush),
              )
            else
              IconButton(
                icon: const Icon(Icons.brush),
                onPressed: () {
                  setState(() => handwritingMode = !handwritingMode);
                  onModeChange(handwritingMode);
                },
              ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              if (handwritingMode)
                Expanded(
                  child: HandSignature(
                    control: handSignatureControl,
                    color: eraserMode ? Colors.white : penColor,
                    width: eraserMode ? 10.0 : penWidth,
                  ),
                )
              else
                Column(
                  children: [
                    // Se asume que la versión de flutter_quill admite esto.
                    // Si no, podrías cambiar a QuillToolbar.basic(...) con showUndo, showRedo, etc.
                    quill.QuillToolbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            quill.QuillToolbarHistoryButton(
                              isUndo: true,
                              controller: quillController,
                            ),
                            quill.QuillToolbarHistoryButton(
                              isUndo: false,
                              controller: quillController,
                            ),
                            quill.QuillToolbarToggleStyleButton(
                              options: const quill.QuillToolbarToggleStyleButtonOptions(),
                              controller: quillController,
                              attribute: quill.Attribute.bold,
                            ),
                            quill.QuillToolbarToggleStyleButton(
                              options: const quill.QuillToolbarToggleStyleButtonOptions(),
                              controller: quillController,
                              attribute: quill.Attribute.italic,
                            ),
                            quill.QuillToolbarToggleStyleButton(
                              options: const quill.QuillToolbarToggleStyleButtonOptions(),
                              controller: quillController,
                              attribute: quill.Attribute.list,
                              value: quill.Attribute.ul,
                            ),
                          ],
                        ),
                      ),
                    ),
                    DropdownButton<String>(
                      value: template,
                      hint: const Text('Plantilla'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('Ninguna')),
                        DropdownMenuItem(value: 'todo', child: Text('Lista de Tareas')),
                        DropdownMenuItem(value: 'meeting', child: Text('Resumen de Reunión')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          template = value!;
                          if (value == 'todo') {
                            quillController.document = quill.Document.fromJson([
                              {'insert': 'Lista de Tareas\n'},
                              {
                                'insert': '- Tarea 1\n',
                                'attributes': {'list': 'bullet'}
                              },
                              {
                                'insert': '- Tarea 2\n',
                                'attributes': {'list': 'bullet'}
                              }
                            ]);
                          } else if (value == 'meeting') {
                            quillController.document = quill.Document.fromJson([
                              {
                                'insert': 'Resumen de Reunión\n',
                                'attributes': {'bold': true}
                              },
                              {'insert': 'Fecha: \n'},
                              {'insert': 'Participantes: \n'},
                              {'insert': 'Notas: \n'},
                            ]);
                          } else {
                            quillController.document = quill.Document();
                          }
                          onTemplateChange?.call(value);
                        });
                      },
                    ),
                    Expanded(
                      child: quill.QuillEditor(
                        controller: quillController,
                        scrollController: ScrollController(),
                        focusNode: FocusNode(),
                        readOnly: false,
                        expands: true,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4.0,
                children: tags
                    .map((tag) => Chip(
                          label: Text(tag),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              tags.remove(tag);
                              onTagsChange(tags);
                            });
                          },
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => _addTag(setState, tags, onTagsChange),
                    child: const Text('Añadir Etiqueta'),
                  ),
                  const Spacer(),
                  if (audioPath != null)
                    IconButton(
                      icon: const Icon(Icons.play_circle),
                      onPressed: () => _playAudio(audioPath!),
                    ),
                  IconButton(
                    icon: const Icon(Icons.mic),
                    onPressed: () async {
                      final path = await _recordAudio();
                      if (path != null) {
                        setState(() {
                          audioPath = path;
                          onAudioChange(audioPath);
                        });
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final time = await _showDateTimePicker(selectedDate);
                  setState(() {
                    reminderTime = time;
                    onReminderChange?.call(time);
                  });
                },
                child: Text(
                  reminderTime != null
                      ? 'Recordatorio: ${DateFormat('dd/MM/yyyy HH:mm').format(reminderTime!)}'
                      : 'Añadir Recordatorio',
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (onFavoriteChange != null)
            IconButton(
              icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              onPressed: () {
                setState(() {
                  isFavorite = !isFavorite;
                  onFavoriteChange(isFavorite);
                });
              },
            ),
          TextButton(
            onPressed: () async {
              selectedDate = (await _showDateTimePicker(selectedDate)) ?? selectedDate;
              setState(() {});
            },
            child: Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(selectedDate)}'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              final content = handwritingMode
                  ? await handSignatureControl.toSvg()
                  : jsonEncode(quillController.document.toDelta().toJson());
              if (content != null && content.isNotEmpty) {
                Navigator.pop(context, {
                  'content': content,
                  'date': selectedDate,
                  'isHandwritten': handwritingMode,
                  'tags': tags,
                  'audioPath': audioPath,
                });
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _addTag(
    void Function(void Function()) setState,
    List<String> tags,
    void Function(List<String>) onTagsChange,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir Etiqueta'),
        content: DropdownButton<String>(
          value: controller.text.isEmpty ? null : controller.text,
          hint: const Text('Selecciona o escribe una etiqueta'),
          isExpanded: true,
          items: _predefinedTags
              .where((tag) => !tags.contains(tag))
              .map((tag) => DropdownMenuItem(value: tag, child: Text(tag)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              controller.text = value;
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty && !tags.contains(controller.text)) {
                setState(() {
                  tags.add(controller.text);
                  onTagsChange(tags);
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  Future<String?> _recordAudio() async {
    // Placeholder de ejemplo: en producción usarías una librería real, p. ej. `flutter_sound`.
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await File(path).writeAsBytes([]);
    return path;
  }

  void _playAudio(String path) async {
    await _audioPlayer.play(DeviceFileSource(path));
  }

  void _showNoteDetails(Note note) {
    final quillController = quill.QuillController(
      document: note.isHandwritten
          ? quill.Document()
          : quill.Document.fromJson(jsonDecode(note.content)),
      selection: const TextSelection.collapsed(offset: 0),
    );
    final handSignatureControl = HandSignatureControl();
    if (note.isHandwritten) {
      final svgData = note.content;
      if (svgData.isNotEmpty) {
        handSignatureControl.draw(SvgParser().parse(svgData));
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.isHandwritten)
              SizedBox(
                height: 200,
                child: HandSignature(
                  control: handSignatureControl,
                  color: Colors.black,
                  width: 2.0,
                ),
              )
            else
              quill.QuillEditor(
                controller: quillController,
                scrollController: ScrollController(),
                focusNode: FocusNode(),
                readOnly: true,
                expands: false,
                padding: EdgeInsets.zero,
              ),
            const SizedBox(height: 8),
            Text(
              'Creada: ${DateFormat('dd/MM/yyyy HH:mm').format(note.date)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (note.tags.isNotEmpty)
              Wrap(
                spacing: 4.0,
                children: note.tags.map((tag) => Chip(label: Text(tag))).toList(),
              ),
            if (note.audioPath != null)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _playAudio(note.audioPath!),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.edit,
                  label: 'Editar',
                  onTap: () {
                    Navigator.pop(context);
                    _editNote(note);
                  },
                ),
                _buildActionButton(
                  icon: Icons.share,
                  label: 'Compartir',
                  onTap: () {
                    Navigator.pop(context);
                    _exportNote(note);
                  },
                ),
                _buildActionButton(
                  icon: Icons.delete,
                  label: 'Eliminar',
                  onTap: () async {
                    Navigator.pop(context);
                    await DatabaseHelper.instance.deleteNote(note.id);
                    if (note.audioPath != null) {
                      await File(note.audioPath!).delete();
                    }
                    _loadNotes();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Icon(icon, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Ordenar por Fecha'),
              trailing: _sortCriteria == 'date'
                  ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                  : null,
              onTap: () {
                setState(() {
                  if (_sortCriteria == 'date') {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortCriteria = 'date';
                    _sortAscending = true;
                  }
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Ordenar por Contenido'),
              trailing: _sortCriteria == 'content'
                  ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                  : null,
              onTap: () {
                setState(() {
                  if (_sortCriteria == 'content') {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortCriteria = 'content';
                    _sortAscending = true;
                  }
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle),
              title: const Text('Ordenar por Completado'),
              trailing: _sortCriteria == 'completed'
                  ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                  : null,
              onTap: () {
                setState(() {
                  if (_sortCriteria == 'completed') {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortCriteria = 'completed';
                    _sortAscending = true;
                  }
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
      initialDateRange: _startDateFilter != null && _endDateFilter != null
          ? DateTimeRange(start: _startDateFilter!, end: _endDateFilter!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDateFilter = picked.start;
        _endDateFilter = picked.end;
        _applyFiltersAndSort();
      });
    }
  }

  Future<DateTime?> _showDateTimePicker(DateTime initialDate) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );
    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );
      if (time != null) {
        return DateTime(date.year, date.month, date.day, time.hour, time.minute);
      }
    }
    return null;
  }

  Future<void> _exportNote(Note note) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Nota: ${DateFormat('dd/MM/yyyy HH:mm').format(note.date)}',
              style: const pw.TextStyle(fontSize: 24),
            ),
            pw.SizedBox(height: 20),
            if (note.isHandwritten)
              pw.Text('Nota manuscrita (ver SVG adjunto)')
            else
              pw.Text(_parseContent(note.content, false)),
            pw.SizedBox(height: 20),
            pw.Text('Etiquetas: ${note.tags.join(', ')}'),
            if (note.audioPath != null) pw.Text('Audio incluido'),
          ],
        ),
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/note_${note.id}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Nota del ${DateFormat('dd/MM/yyyy').format(note.date)}',
    );
  }

  Future<void> _exportAllNotes() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        build: (pw.Context context) => [
          pw.Text('Todas las Notas', style: const pw.TextStyle(fontSize: 24)),
          pw.SizedBox(height: 20),
          ..._filteredNotes.map(
            (note) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(note.date)}'),
                pw.Text('Contenido: ${note.isHandwritten ? 'Nota manuscrita' : _parseContent(note.content, false)}'),
                pw.Text('Etiquetas: ${note.tags.join(', ')}'),
                if (note.audioPath != null) pw.Text('Audio incluido'),
                pw.SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/all_notes_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Exportación de todas las notas',
    );
  }
}
