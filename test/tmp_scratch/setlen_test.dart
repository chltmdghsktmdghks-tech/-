import 'package:music_doodle_engine/edit_ops.dart';
void main() {
  final notes = <List<Object?>>[[5,4,2,2],[5,8,2,2]];
  print('setLen 8칸으로: ${NoteOps.setLen(notes,5,4,8,steps:32)}');
  print('stretchAll +1 : ${NoteOps.stretchAll(notes,1,steps:32)}');
  print('move 오른쪽 끝으로: ${NoteOps.move([[5,28,4,2]],5,28,3,steps:32)}');
  print('  되돌아오기   : ${NoteOps.move(NoteOps.move([[5,28,4,2]],5,28,3,steps:32),5,31,-3,steps:32)}');
  print('add 이웃 위 덮기: ${NoteOps.add([[5,10,2,2]],5,9,isChord:false,steps:32)}');
}
