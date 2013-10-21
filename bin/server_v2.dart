library server;

import 'package:http_server/http_server.dart';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:route/server.dart';
import 'package:path/path.dart' as path;
import 'package:wordherd/persistable_io.dart' as db;
import 'package:wordherd/shared_io.dart';
import 'dart:convert' show JSON;
import 'dart:async';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:serialization/serialization.dart';
import 'package:google_oauth2_client/google_oauth2_console.dart' as oauth2;
import 'package:google_plus_v1_api/plus_v1_api_console.dart';

part 'oauth_handler.dart';

final Logger log = new Logger('Server');
final Serialization serializer = new Serialization();

configureLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord logRecord) {
    StringBuffer sb = new StringBuffer();
    sb
    ..write(logRecord.time.toString())..write(":")
    ..write(logRecord.loggerName)..write(":")
    ..write(logRecord.level.name)..write(":")
    ..write(logRecord.sequenceNumber)..write(": ")
    ..write(logRecord.message.toString());
    if (logRecord.exception != null) {
      sb
      ..write(": ")
      ..write(logRecord.exception);
    }
    print(sb.toString());
  });
}

Boards boards;

main() {
  configureLogger();

  String dbUrl;
  if (Platform.environment['DATABASE_URL'] != null) {
    dbUrl = Platform.environment['DATABASE_URL'];
  } else {
    String user = Platform.environment['USER'];
    dbUrl = 'postgres://$user:@localhost:5432/$user';
  }
  
  log.info("DB URL is $dbUrl");
  
  String root = path.join(path.dirname(path.current), 'web');
  
  runZoned(() {
    
    db.init(dbUrl)
    .then((_) => loadData())
    .then((_) => HttpServer.bind('0.0.0.0', 8765))
    .then((HttpServer server) {
      
      VirtualDirectory staticFiles = new VirtualDirectory(root)
        ..followLinks = true;
      
      new Router(server)
        ..filter(new RegExp(r'^.*$'), addCorsHeaders)
        ..serve('/session', method: 'GET').listen(oauthSession)
        ..serve('/connect', method: 'POST').listen(oauthConnect) // TODO use HttpBodyHandler when dartbug.com/14259 is fixed
        ..serve('/register', method: 'POST')
          .transform(new HttpBodyHandler()).listen(registerPlayer)
        ..serve('/matches', method: 'GET')
          .transform(new HttpBodyHandler()).listen(listMatches)
        ..serve('/matches', method: 'POST')
          .transform(new HttpBodyHandler()).listen(createMatch)

        // BUG: https://code.google.com/p/dart/issues/detail?id=14196
        ..defaultStream.listen(staticFiles.serveRequest);
      
      log.info('Server running');
    });
    
  },
  onError: (e) => log.severe("Error handling request: $e"));

}

Future loadData() {
  File boardData = new File('dense1000FINAL.txt');
  return boardData.readAsString().then((String data) => boards = new Boards(data));
}

Future<bool> addCorsHeaders(HttpRequest req) {
  log.fine('Adding CORS headers for ${req.method} ${req.uri}');
  log.fine(new List.from(req.cookies).toString());
  req.response.headers.add('Access-Control-Allow-Origin', 'http://127.0.0.1:3030');
  req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
  req.response.headers.add('Access-Control-Allow-Credentials', 'true');
  if (req.method == 'OPTIONS') {
    req.response.statusCode = 200;
    req.response.close(); // TODO: wait for this?
    return new Future.sync(() => false);
  } else {
    return new Future.sync(() => true);
  }
}

void registerPlayer(HttpRequestBody body) {
  log.fine('Register player');
  Map data = body.body;
  String gplusId = data['gplus_id'];
  
  db.Persistable.findOneBy(Player, {'gplus_id':gplusId}).then((Player p) {
    if (p == null) {
      Player player = new Player()
      ..gplus_id = data['gplus_id']
      ..name = data['name'];
      return player.store().then((_) => body.response.statusCode = 201);
    } else {
      body.response.statusCode = 200;
      return true;
    }
  })
  .then((_) {
    log.fine('All done registering');
    body.response.close();
  })
  .catchError((e) => _handleError(body, e));
}

void createMatch(HttpRequestBody body) {
  log.fine('Create match');
  Map data = body.body;
  
  Match match = new Match()
      ..p1_id = data['p1_id']
      ..p2_id = data['p2_id']
      ..board = boards.generateBoard();
  match.store().then((_) {
    body.response.statusCode = 201;
    body.response.close();
  })
  .catchError((e) => _handleError(body, e));
}

void listMatches(HttpRequestBody body) {
  log.fine('Listing matches');
  db.Persistable.all(Match).toList().then((List<Match> matches) {
    String json = JSON.encode(serializer.write(matches));
    body.response.headers.contentType = ContentType.parse('application/json');
    body.response.contentLength = json.length;
    body.response.write(json);
    body.response.close();
  })
  .catchError((e) => _handleError(body, e));
}

void _handleError(HttpRequestBody body, e) {
  log.severe('Oh noes! $e', getAttachedStackTrace(e));
  body.response.statusCode = 500;
  body.response.close();
}

Future<Person> getCurrentPerson(String accessToken) {
  Plus plusclient = makePlusClient(accessToken);
  return plusclient.people.get('me');
}

Plus makePlusClient(String accessToken) {
  SimpleOAuth2 simpleOAuth2 = new SimpleOAuth2()
      ..credentials = new oauth2.Credentials(accessToken);
  Plus plusclient = new Plus(simpleOAuth2);
  plusclient.makeAuthRequests = true;
  return plusclient;
}