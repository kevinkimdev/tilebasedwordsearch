part of tilebasedwordsearch;

class BoardController {
  final Board board;
  final BoardView view;

  BoardController(this.board, this.view);

  List<int> selectedPath;
  String _keyboardSearchString = '';

  void clearSelected() {
    view.selectedTiles.clear();
    selectedPath = null;
  }

  void clearKeyboardInput() {
    _keyboardSearchString = '';
  }

  int _comparePaths(List<int> a, List<int> b) {
    int aLength = a.length;
    int bLength = b.length;
    if (aLength != bLength) {
      return aLength - bLength;
    }
    for (int i = 0; i < aLength; i++) {
      int diff = a[i] - b[i];
      if (diff != 0) {
        return diff;
      }
    }
    return 0;
  }

  List<List<int>> sortPathSet(Set<List<int>> paths) {
    List out = paths.toList();
    out.sort(_comparePaths);
    return out;
  }

  void updateFromKeyboard() {
    clearSelected();
    if (_keyboardSearchString.length == 0) {
      return;
    }
    Set<List<int>> paths = new Set<List<int>>();

    // Find the best path.
    List<int> bestPath;
    int bestScore = 0;
    if (board.config.stringInGrid(_keyboardSearchString, paths)) {
      List listOfPaths = sortPathSet(paths);
      listOfPaths.forEach((path) {
        int pathScore = board.scoreForPath(path);
        if (pathScore > bestScore) {
          bestPath = path;
          bestScore = pathScore;
        }
      });
    }
    if (bestPath != null) {
      selectedPath = bestPath;
      for (int i = 0; i < selectedPath.length; i++) {
        view.selectedTiles.add(selectedPath[i]);
      }
    }
  }

  String translateKeyboardButtonId(int buttonId) {
    if (buttonId >= Keyboard.A && buttonId <= Keyboard.Z) {
      return new String.fromCharCode(buttonId);
    }
    return '';
  }

  bool keyboardEventInterceptor(DigitalButtonEvent event, bool repeat) {
    if (repeat == true) {
      return true;
    }
    if (event.down == false) {
      return true;
    }
    if (event.buttonId == Keyboard.ESCAPE ||
        event.buttonId == Keyboard.SPACE) {
      // Space or escape kills the current word search.
      // TODO: Indicate in GUI.
      clearKeyboardInput();
      return true;
    }
    if (event.buttonId == Keyboard.ENTER) {
      // Submit.
      board.attemptPath(selectedPath);
      clearKeyboardInput();
      return true;
    }
    String newSearchString = _keyboardSearchString +
                             translateKeyboardButtonId(event.buttonId);
    if (event.buttonId < Keyboard.A || event.buttonId > Keyboard.Z) {
      return true;
    }
    if (board.config.stringInGrid(newSearchString, null)) {
      _keyboardSearchString = newSearchString;
    } else if (event.buttonId == Keyboard.Q &&
               board.config.stringInGrid(newSearchString + 'U', null)) {
      _keyboardSearchString = newSearchString;
    } else {
      while (_keyboardSearchString.length > 0) {
        if (_keyboardSearchString[_keyboardSearchString.length-1] == 'Q') {
          _keyboardSearchString =
              _keyboardSearchString.substring(0,_keyboardSearchString.length-1);
        } else {
          break;
        }
      }
    }
    return true;
  }

  void updateFromTouch(GameLoopTouch touch) {
    double scaleX = view.scaleX;
    double scaleY = view.scaleY;
    if (touch != null) {
      // If we have a touch, ignore keyboard input.
      clearKeyboardInput();
      clearSelected();
      for (var position in touch.positions) {
        int x = (position.x * scaleX).toInt();
        int y = (position.y * scaleY).toInt();
        for (int i = 0; i < GameConstants.BoardDimension; i++) {
          for (int j = 0; j < GameConstants.BoardDimension; j++) {
            int index = GameConstants.rowColumnToIndex(i, j);
            if (view.selectedTiles.contains(index)) {
              continue;
            }
            var transform = view.getTileRectangle(i, j);
            if (transform.contains(x, y)) {
              view.selectedTiles.add(index);
              selectedPath.add(index);
            }
          }
        }
      }
    }
  }

  void update(GameLoopTouch touch) {
    clearSelected();
    updateFromKeyboard();
    updateFromTouch(touch);
  }
}