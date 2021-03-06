library wordherd_shared;

import 'package:observe/observe.dart';
import 'dart:math' show Random;
import 'persistable_html.dart' show Persistable, serialized;

// Turn on mirrors used for serialization
@MirrorsUsed(targets: const ['wordherd_shared', 'serialization', 'persistable'],
             override: 'mirrors_helpers')
import 'dart:mirrors';

part 'src/shared/game.dart';
part 'src/shared/board.dart';
part 'src/shared/game_match.dart';
part 'src/shared/boards.dart';
part 'src/shared/game_constants.dart';
part 'src/shared/player.dart';
part 'src/shared/game_solo.dart';