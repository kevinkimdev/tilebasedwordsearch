library hello_static;

import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:json' as JSON;

import "package:logging/logging.dart";
import "package:fukiya/fukiya.dart";

import 'package:tilebasedwordsearch/shared_io.dart';
import 'package:tilebasedwordsearch/persistable_io.dart' as db;
import "package:google_oauth2_client/google_oauth2_console.dart" as console_auth;
import "package:google_plus_v1_api/plus_v1_api_console.dart";
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import "package:html5lib/dom.dart";
import "package:html5lib/dom_parsing.dart";

// Needs to be the same one used on the client side.
final String CLIENT_ID = "250963735330.apps.googleusercontent.com";
final String CLIENT_SECRET = "u-Bk_3yhNjC6YCg7-yG6XeoL";

final String TOKENINFO_URL = "https://www.googleapis.com/oauth2/v1/tokeninfo";
final String TOKEN_ENDPOINT = 'https://accounts.google.com/o/oauth2/token';
final String TOKEN_REVOKE_ENDPOINT = 'https://accounts.google.com/o/oauth2/revoke';

final Random random = new Random();
final Logger _log = new Logger("server");
final String INDEX_HTML = "./web/out/index.html";

Fukiya fukiya;
Boards boards;

void main() {
  _setupLogger();

  _log.fine("Starting Server");

  var port = Platform.environment['PORT'] != null ?
      int.parse(Platform.environment['PORT'], onError: (_) => 8080) :
      8080;

  var dbUrl;
  if (Platform.environment['DATABASE_URL'] != null) {
    dbUrl = Platform.environment['DATABASE_URL'];
  } else {
    var user = Platform.environment['USER'];
    dbUrl = 'postgres://$user:@localhost:5432/$user';
  }

  db.init(dbUrl)
  .then((_) {
    var path = new Path(new Options().script).directoryPath.append('..').append('boardgen').append('dense1000.txt');
    _log.fine("boardgen = ${path}");
    return new File.fromPath(path).readAsString();
  }, onError: (e) {
    _log.fine('Error connecting to db: $e');
    return new Future.error(e);
  })
  .then((String lines) {
    boards = new Boards(lines);
  })
  .then((_) {
    _log.fine('DB connected, now starting up web server');

    fukiya = new Fukiya()
    ..get('/', getIndexHandler)
    // This will just catch the static index.html, we dont want that.
    // Bug reported.
    // ..get('/index.html', getIndexHandler)
    ..get('/index', getIndexHandler)
    ..post('/connect', postConnectDataHandler)
    ..post('/disconnect', postDisconnectHandler)
    ..get('/multiplayer_games/new', getNewMultiplayerGame)
    ..staticFiles('./web/out')
    ..use(new FukiyaJsonParser())
    ..listen('0.0.0.0', port);
  })
  .catchError((e) => _log.fine("error starting up: $e"));
}

/**
 * Revoke current user's token and reset their session.
 */
void postDisconnectHandler(FukiyaContext context) {
  _log.fine("postDisconnectHandler");
  _log.fine("context.request.session = ${context.request.session}");

  String tokenData = context.request.session.containsKey("access_token") ?
      context.request.session["access_token"] : null;

  if (tokenData == null) {
    context.response.statusCode = 401;
    context.send("Current user not connected.");
    return;
  }

  final String revokeTokenUrl = "${TOKEN_REVOKE_ENDPOINT}?token=${tokenData}";
  context.request.session.remove("access_token");

  new http.Client()
  ..get(revokeTokenUrl).then((http.Response response) {
    _log.fine("GET ${revokeTokenUrl}");
    _log.fine("Response = ${response.body}");
    context.request.session["state_token"] = _createStateToken();
    Map data = {
                "state_token": context.request.session["state_token"],
                "message" : "Successfully disconnected."
                };
    context.send(JSON.stringify(data));
  });
}

/**
 * Sends the client a index file with state token and starts the client
 * side authentication process.
 */
void getIndexHandler(FukiyaContext context) {
  _log.fine("getIndexHandler");
  // Create a state token.
  context.request.session["state_token"] = _createStateToken();

  // Readin the index file and add state token into the meta element.
  // TODO: cache the INDEX_HTML file into memory
  var file = new File(INDEX_HTML);
  file.exists().then((bool exists) {
    if (exists) {
      file.readAsString().then((String indexDocument) {
        Document doc = new Document.html(indexDocument);
        Element metaState = new Element.html('<meta name="state_token" content="${context.request.session["state_token"]}">');
        doc.head.children.add(metaState);
        context.response.write(doc.outerHtml);
        context.response.done.catchError((e) => _log.fine("File Response error: ${e}"));
        context.response.close();
      }, onError: (error) => _log.fine("error = $error"));
    } else {
      _log.fine("getIndexHandler exists = $exists");
      context.response.statusCode = 404;
      context.response.close();
    }
  })
  .catchError((e) => _log.fine("error: $e"));
}

/**
 * Returns a list of friends that have also installed the game.
 */
void getNewMultiplayerGame(FukiyaContext context) {
//  int playerId = context.request.session['player_id'].toInt();
//  db.Persistable.load(playerId, Player).then((Player player) {
//    
//  })
//  .catchError((e) {
//    _log.warning('Problem loading player $playerId: $e');
//    context.response.statusCode = 404;
//    context.response.close();
//  });
  String accessToken = context.request.session["access_token"];
  getAllFriends(accessToken).then((people) {
    _log.fine('Found friends of current player: $people');
    context.response.headers.add(HttpHeaders.CONTENT_TYPE, 'application/json');
    context.response.write(JSON.stringify(people));
    context.response.close();
  })
  .catchError((e) {
    _log.warning('Problem finding friends: $e');
    context.response.statusCode = 500;
    context.response.close();
  });
}

/**
 * Upgrade given auth code to token, and store it in the session.
 * POST body of request should be the authorization code.
 * Example URI: /connect?state=...&gplus_id=...
 */
void postConnectDataHandler(FukiyaContext context) {
  _log.fine("postConnectDataHandler");
  _confirmOauthSignin(context).then((String userId) {
    db.Persistable.findBy(Player, {'gplus_id': userId}).toList().then((List players) {
      if (players.isEmpty) {
        _log.info('No player found for gplusId $userId');
        var p = new Player()..gplus_id = userId;
        p.store().then((_) {
          context.request.session['player_id'] = p.dbId;
          context.send("POST OK");
        })
        .catchError((e) {
          _log.severe('Did not store new person $userId into db: $e');
          context.response.statusCode = 500;
          context.response.close();
        });
      } else {
        _log.info('Found the player ${players.first}');
      }
    });
  });
}

Future<String> _confirmOauthSignin(FukiyaContext context) {

  String tokenData = context.request.session["access_token"]; // TODO: handle missing token
  String stateToken = context.request.session["state_token"];
  String queryStateToken = context.request.uri.queryParameters["state_token"];
  
  // Check if the token already exists for this session.
  if (tokenData != null) {
    context.send("Current user is already connected.");
    return new Future.value(context.request.uri.queryParameters["gplus_id"]);
  }
  
  // Check if any of the needed token values are null or mismatched.
  if (stateToken == null || queryStateToken == null || stateToken != queryStateToken) {
    context.response.statusCode = 401;
    context.send("Invalid state parameter: $stateToken $queryStateToken");
    return new Future.error('Invalid state parameter: $stateToken $queryStateToken');
  }
  
  Completer completer = new Completer();
  
  // Normally the state would be a one-time use token, however in our
  // simple case, we want a user to be able to connect and disconnect
  // without reloading the page.  Thus, for demonstration, we don't
  // implement this best practice.
  context.request.session.remove("state_token");
  
  String gPlusId = context.request.uri.queryParameters["gplus_id"];
  StringBuffer sb = new StringBuffer();
  // Read data from request.
  context.request
  .transform(new StringDecoder())
  .listen((data) => sb.write(data), onDone: () {
    _log.fine("context.request.listen.onDone = ${sb.toString()}");
    Map requestData = JSON.parse(sb.toString());
  
    Map fields = {
              "grant_type": "authorization_code",
              "code": requestData["code"],
              // http://www.riskcompletefailure.com/2013/03/postmessage-oauth-20.html
              "redirect_uri": "postmessage",
              "client_id": CLIENT_ID,
              "client_secret": CLIENT_SECRET
    };
  
    _log.fine("fields = $fields");
    http.Client _httpClient = new http.Client();
    _httpClient.post(TOKEN_ENDPOINT, fields: fields).then((http.Response response) {
      // At this point we have the token and refresh token.
      var credentials = JSON.parse(response.body);
      _log.fine("credentials = ${response.body}");
      _httpClient.close();
  
      var verifyTokenUrl = '${TOKENINFO_URL}?access_token=${credentials["access_token"]}';
      new http.Client()
      ..get(verifyTokenUrl).then((http.Response response)  {
        _log.fine("response = ${response.body}");
  
        var verifyResponse = JSON.parse(response.body);
        String userId = verifyResponse["user_id"];
        String accessToken = credentials["access_token"];
        if (userId != null && userId == gPlusId && accessToken != null) {
          context.request.session["access_token"] = accessToken;
          
          _log.info('Set the access token to $accessToken');
          
          completer.complete(userId);
        } else {
          context.response.statusCode = 401;
          context.send("POST FAILED ${userId} != ${gPlusId}");
          completer.completeError("POST FAILED ${userId} != ${gPlusId}");
        }
      });
    });
  });
  
  return completer.future;
}

/**
 * Logger configuration.
 */
void _setupLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord logRecord) {
    StringBuffer sb = new StringBuffer();
    sb
    ..write(logRecord.time.toString())..write(":")
    ..write(logRecord.loggerName)..write(":")
    ..write(logRecord.level.name)..write(":")
    ..write(logRecord.sequenceNumber)..write(": ")
    ..write(logRecord.message.toString());
    print(sb.toString());
  });
}

/**
 * Creating state token based on random number.
 */
String _createStateToken() {
  StringBuffer stateTokenBuffer = new StringBuffer();
  new MD5()
  ..add(random.nextDouble().toString().codeUnits)
  ..close().forEach((int s) => stateTokenBuffer.write(s.toRadixString(16)));
  String stateToken = stateTokenBuffer.toString();
  return stateToken;
}

Future<List<Person>> getAllFriends(String accessToken) {
  
  List<Person> people = <Person>[];
  Completer completer = new Completer();
  
  consumePeople([String nextToken]) {
    return getPageOfFriends(accessToken, nextPageToken: nextToken)
      .then((PeopleFeed feed) {
        people.addAll(feed.items);
        if (feed.nextPageToken != null) {
          return consumePeople(feed.nextPageToken);
        } else {
          completer.complete(people);
        }
      });
  }
  
  consumePeople().catchError(completer.completeError);
  
  return completer.future;
}

Future<PeopleFeed> getPageOfFriends(String accessToken,
    {String orderBy: 'best', int maxResults: 100, String nextPageToken}) {
  SimpleOAuth2 simpleOAuth2 = new SimpleOAuth2()
      ..credentials = new console_auth.Credentials(accessToken);
  Plus plusclient = new Plus(simpleOAuth2);
  plusclient.makeAuthRequests = true;
  
  return plusclient.people.list('me', 'visible', orderBy: orderBy,
      maxResults: maxResults, pageToken: nextPageToken);
}

/**
 * Simple OAuth2 class for making requests and storing credentials in memory.
 */
class SimpleOAuth2 implements console_auth.OAuth2Console {
  final Logger logger = new Logger("SimpleOAuth2");

  /// The URL from which the pub client will request an access token once it's
  /// been authorized by the user.
  Uri _tokenEndpoint = Uri.parse('https://accounts.google.com/o/oauth2/token');
  Uri get tokenEndpoint => _tokenEndpoint;

  console_auth.Credentials _credentials;
  console_auth.Credentials get credentials => _credentials;
  void set credentials(value) {
    _credentials = value;
  }
  console_auth.SystemCache _systemCache;
  console_auth.SystemCache get systemCache => _systemCache;

  void clearCredentials(console_auth.SystemCache cache) {
    logger.fine("clearCredentials(console_auth.SystemCache $cache)");
  }

  Future withClient(Future fn(console_auth.Client client)) {
    logger.fine("withClient(Future ${fn}(console_auth.Client client))");
    console_auth.Client _httpClient = new console_auth.Client(CLIENT_ID, CLIENT_SECRET, _credentials);
    return fn(_httpClient);
  }

  void close() {
    logger.fine("close()");
  }
}
