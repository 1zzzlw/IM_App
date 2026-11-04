import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/models.dart';
import '../../ui/components.dart';
import 'agent_person_page.dart' show agentRequestId;

class AgentCallPage extends StatefulWidget {
  const AgentCallPage({super.key, required this.name});
  final String name;
  @override
  State<AgentCallPage> createState() => _AgentCallPageState();
}

class _AgentCallPageState extends State<AgentCallPage> {
  final recorder = AudioRecorder(), player = AudioPlayer();
  StreamSubscription<Amplitude>? amplitude;
  Timer? poll;
  String callId = '', phase = '正在呼叫…', caption = '';
  int epoch = 0, generation = 0;
  bool closed = false, speaking = false, rotating = false, outputting = false;
  DateTime? speechStart, silenceStart, recordStart;
  File? recordingFile, playFile;
  Future<void> interrupting = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => begin());
  }

  @override
  void dispose() {
    closed = true;
    generation++;
    poll?.cancel();
    amplitude?.cancel();
    recorder.dispose();
    player.dispose();
    super.dispose();
  }

  void status(String text) {
    if (mounted) setState(() => phase = text);
  }

  Future<void> begin() async {
    final app = AppScope.of(context);
    try {
      if (!await recorder.hasPermission()) throw StateError('请允许使用麦克风');
      final call = asJson(
        await app.api.post(
          '/ai-message/calls',
          data: {'userId': app.user!.id, 'clientCallId': agentRequestId()},
        ),
      );
      callId = str(call['id']);
      epoch = number(call['epoch']).toInt();
      if (call['status'] != 'connected') {
        status('对方暂时没有接听');
        return;
      }
      await startRecord();
      status('正在聆听…');
      amplitude = recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((value) {
            if (closed || rotating) return;
            final now = DateTime.now();
            if (value.current > -32) {
              silenceStart = null;
              if (!speaking) {
                speaking = true;
                speechStart = now;
                generation++;
                player.stop();
                outputting = false;
                interrupting = interrupting
                    .then((_) async {
                      final result = asJson(
                        await app.api.post(
                          '/ai-message/calls/$callId/interrupt',
                          data: {'userId': app.user!.id, 'epoch': epoch},
                        ),
                      );
                      epoch = number(result['epoch']).toInt();
                    })
                    .catchError((Object e) {
                      status(e.toString());
                    });
                status('正在听你说');
              }
            } else if (speaking) {
              silenceStart ??= now;
              if (now.difference(silenceStart!).inMilliseconds > 800) {
                speaking = false;
                rotate(true);
              }
            }
            if (recordStart != null &&
                now.difference(recordStart!).inSeconds >= 25) {
              final hadSpeech = speaking;
              speaking = false;
              rotate(hadSpeech);
            }
          });
      poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final state = asJson(
            await app.api.get(
              '/ai-message/calls/$callId',
              query: {'userId': app.user!.id},
            ),
          );
          if (state['status'] != 'connected') {
            status('通话已结束');
            await stopLocal();
          }
        } catch (_) {}
      });
    } catch (e) {
      status(e.toString());
      await stopLocal();
    }
  }

  Future<void> startRecord() async {
    if (closed) return;
    final directory = await getTemporaryDirectory();
    recordingFile = File(
      '${directory.path}/agent_call_${agentRequestId()}.wav',
    );
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: recordingFile!.path,
    );
    recordStart = DateTime.now();
  }

  Future<void> rotate(bool send) async {
    if (closed || rotating) return;
    rotating = true;
    final version = generation;
    final path = await recorder.stop();
    await startRecord();
    rotating = false;
    if (path == null) return;
    final file = File(path);
    if (send) {
      unawaited(turn(file, version));
    } else {
      await file.delete().catchError((_) => file);
    }
  }

  Future<void> turn(File file, int version) async {
    final app = AppScope.of(context);
    try {
      await interrupting;
      if (closed || version != generation) return;
      final response = asJson(
        await app.api.post(
          '/ai-message/calls/$callId/turn',
          data: FormData.fromMap({
            'userId': app.user!.id,
            'epoch': epoch,
            'file': MultipartFile.fromBytes(
              await file.readAsBytes(),
              filename: 'voice.wav',
            ),
          }),
        ),
      );
      if (closed || version != generation) return;
      epoch = number(response['epoch']).toInt();
      if (response['status'] != 'connected') {
        status('通话已结束');
        await stopLocal();
        return;
      }
      if (mounted) setState(() => caption = str(response['transcript']));
      for (final segment in asList(response['segments'])) {
        if (closed || version != generation) break;
        final result = await app.api.response(
          'GET',
          '/ai-message/media/${segment['assetId']}',
          query: {'userId': app.user!.id},
          type: ResponseType.bytes,
        );
        app.api.unwrap(result);
        if (closed || version != generation) break;
        final directory = await getTemporaryDirectory();
        playFile = File('${directory.path}/agent_play_${agentRequestId()}.wav');
        await playFile!.writeAsBytes(List<int>.from(result.data));
        await player.setFilePath(playFile!.path);
        status('正在说话');
        outputting = true;
        final completed = Completer<bool>();
        final sub = player.playerStateStream.listen((state) {
          if (!completed.isCompleted &&
              state.processingState == ProcessingState.completed) {
            completed.complete(true);
          } else if (!completed.isCompleted &&
              !state.playing &&
              state.processingState == ProcessingState.idle) {
            completed.complete(false);
          }
        });
        unawaited(player.play());
        final heard = await completed.future.timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        await sub.cancel();
        outputting = false;
        if (heard && !closed && version == generation) {
          await app.api.post(
            '/ai-message/calls/$callId/heard',
            data: {
              'userId': app.user!.id,
              'epoch': epoch,
              'segmentId': segment['id'],
            },
          );
        }
        await playFile!.delete().catchError((_) => playFile!);
      }
      if (!closed && version == generation) status('正在聆听…');
    } catch (e) {
      if (!closed && version == generation) status(e.toString());
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> stopLocal() async {
    closed = true;
    generation++;
    poll?.cancel();
    await amplitude?.cancel();
    await player.stop();
    if (await recorder.isRecording()) await recorder.stop();
  }

  Future<void> hangup() async {
    final app = AppScope.of(context);
    await stopLocal();
    if (callId.isNotEmpty) {
      await app.api
          .post('/ai-message/calls/$callId/end', data: {'userId': app.user!.id})
          .catchError((_) {
            return null;
          });
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) hangup();
    },
    child: PageScaffold(
      title: '语音通话',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline_rounded, size: 80),
              const SizedBox(height: 24),
              Text(widget.name, style: const TextStyle(fontSize: 26)),
              const SizedBox(height: 20),
              Text(phase),
              const SizedBox(height: 16),
              Text(caption, textAlign: TextAlign.center),
              const SizedBox(height: 40),
              FilledButton(onPressed: hangup, child: const Text('挂断')),
            ],
          ),
        ),
      ),
    ),
  );
}
