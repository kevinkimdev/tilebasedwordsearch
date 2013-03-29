import 'dart:html';
import 'dart:math';
import 'package:game_loop/game_loop.dart';
import 'package:asset_pack/asset_pack.dart';
import 'package:web_ui/web_ui.dart';

import 'package:tilebasedwordsearch/tilebasedwordsearch.dart';

CanvasElement _canvasElement;
GameLoop _gameLoop;
AssetManager assetManager = new AssetManager();
Dictionary dictionary;
BoardView _boardView;
@observable Game game;

@observable bool ready = false;

void drawCircle(int x, int y) {
  var context = _canvasElement.getContext('2d');
  context.beginPath();
  context.arc(x, y, 20.0, 0, 2 * PI);
  context.fillStyle = 'green';
  context.fill();
}

void initialize() {
  dictionary = new Dictionary.fromFile(assetManager['game.dictionary']);
}

void startNewGame() {
  game = new Game(dictionary);
}

void gameUpdate(GameLoop gameLoop) {
  _boardView.update(currentTouch);
  // game.tick(gameLoop.dt);
}

void gameRender(GameLoop gameLoop) {
  _boardView.render();
  if (currentTouch == null) {
    return;
  }
  var transform = new RectangleTransform(_canvasElement);
  currentTouch.positions.forEach((position) {
    int x = position.x;
    int y = position.y;
    if (transform.contains(x, y)) {
      int rx = transform.transformX(x);
      int ry = transform.transformY(y);
      drawCircle(rx, ry);
    }
  });
}

GameLoopTouch currentTouch;

void gameTouchStart(GameLoop gameLoop, GameLoopTouch touch) {
  if (currentTouch == null) {
    currentTouch = touch;
  }
}

void gameTouchEnd(GameLoop gameLoop, GameLoopTouch touch) {
  if (touch == currentTouch) {
    currentTouch = null;
  }
}

main() {
  print('Touch events supported? ${TouchEvent.supported}');
  _canvasElement = query('#frontBuffer');

  _boardView = new BoardView(_canvasElement);
  _gameLoop = new GameLoop(_canvasElement);
  // Don't lock the pointer on a click.
  _gameLoop.pointerLock.lockOnClick = false;
  _gameLoop.onUpdate = gameUpdate;
  _gameLoop.onRender = gameRender;
  _gameLoop.onTouchStart = gameTouchStart;
  _gameLoop.onTouchEnd = gameTouchEnd;
  assetManager.loadPack('game', '../assets.pack')
      .then((_) => initialize())
      .then((_) => _gameLoop.start());
}
