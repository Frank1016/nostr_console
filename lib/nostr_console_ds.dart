
import 'dart:io';
import 'dart:convert';
//import 'dart:svg';

const int  screenWidth = 80;
const bool enableVerticalLines = false;
const int  spacesPerDepth = 8;
int    keyLenPrinted    = 6;
String defaultServerUrl = 'wss://nostr.onsats.org';

Map<String, String> gKindONames = {};

void getNames(Event e) {
  if( e.eventData.kind != 0) {
    return;
  }

  print("In getNames: for event content: ${e.eventData.content}");
  //e.printEvent(0);
  String name = "";
  String content = e.eventData.content;
  if( content.isEmpty) {
    return;
  }
  dynamic json = jsonDecode(content);
  
  gKindONames[e.eventData.pubkey] = json["name"];
}

String getAuthorName(String pubkey) {
  String max3(String v) => v.length > 3? v.substring(0,3) : v.substring(0, v.length);
  String name = max3(pubkey);
  name = gKindONames[pubkey]??name;
  return name;
}

void printDepth(int d) {
  if( d == 0) {
    return;
  }

  for( int i = 0; i < spacesPerDepth * d ; i++) {
    stdout.write(" ");
  }
 }

String rightShiftContent(String s, int numSpaces) {
  String newString = "";
  int    newlineCounter = 0;
  String spacesString = "";

  for( int i = 0; i < numSpaces ; i++) {
    spacesString += " ";
  }

  for(int i = 0; i < s.length; i++) {
    if( s[i] == '\n') {
      newString += "\n";
      newString += spacesString;
      newlineCounter = 0;
    } else {
      if( newlineCounter >= (screenWidth - numSpaces)) {
        newString += "\n";
        newString += spacesString;
        newlineCounter = 0;
      } 
      newString += s[i];
    }
    newlineCounter++;
  }
  return newString;
}

class Contact {
  String id;
  String relay;
  String name;
  Contact(this.id, this.relay, this.name);
  factory Contact.fromJson(dynamic json) {
    return Contact(json[1] as String, json[2] as String, json[3]);
  }
}

class EventData {
  String id;
  String pubkey;
  int    createdAt;
  int    kind;
  String content;
  String eTagParent; // direct parent tag
  List<String> eTagsRest;// rest of e tags
  List<String> pTags;// list of p tags for kind:1

  List<Contact> contactList = []; // used for kind:3 events, which is contact list event
  
  String getParent() {
    if( eTagParent != "") {
      return eTagParent;
    }
    if( eTagsRest.length > 0) {
      return eTagsRest[eTagsRest.length - 1];
    }
    return "";
  }

  EventData(this.id, this.pubkey, this.createdAt, this.kind, this.content, this.eTagParent, this.eTagsRest, this.pTags, this.contactList);
  
  factory EventData.fromJson(dynamic json) {
    List<Contact> contactList = [];

    List<String> eTagsRead = [];
    List<String> pTagsRead = [];
    String       eTagParentRead = "";

    var jsonTags = json['tags'];      
    var numTags = jsonTags.length;
        
    // NIP 02: if the event is a contact list type, then populate contactList
    if(json['kind'] == 3) {
      for( int i = 0; i < numTags; i++) {
        var tag = jsonTags[i];
        var n = tag.length;
        String server = defaultServerUrl;
        if( n >=3 ) {
          server = tag[2].toString();
          if( server == 'wss://nostr.rocks') {
            server = 'wss://nostr.onsats.org';
          }
        }
        Contact c = Contact(tag[1] as String, server, 3.toString());
        contactList.add(c);
      }
    } else {
      if ( json['kind'] == 1) {
        for( int i = 0; i < numTags; i++) {
          var tag = jsonTags[i];
          //stdout.write(tag);
          //print(tag.runtimeType);
          if( tag[0] == "e") {
            eTagsRead.add(tag[1]);
          } else {
            if( tag[0] == "p") {
              pTagsRead.add(tag[1]);
            }
          }
          // TODO add other tags
        }
      }
    }
    return EventData(json['id'] as String,      json['pubkey'] as String, 
                     json['created_at'] as int, json['kind'] as int,
                     json['content'] as String, eTagParentRead,
                     eTagsRead,                 pTagsRead,
                     contactList);
  }

  void printEventData(int depth) {
    String max3(String v) => v.length > 3? v.substring(0,3) : v.substring(0, v.length);
    DateTime dTime = DateTime.fromMillisecondsSinceEpoch(createdAt *1000);
    if( createdAt == 0) {
      print("debug: createdAt == 0 for event $content");
    }

    String contentShifted = rightShiftContent(content, spacesPerDepth * depth + 10);
    void printGreen(String s) => stdout.write("\x1B[32m$s\x1B[0m");
    printDepth(depth);
    stdout.write("+-------+-------------\n");
    printDepth(depth);
    stdout.write("|Message: ");
    printGreen("$contentShifted\n");
    printDepth(depth);
    String name = getAuthorName(pubkey);
    stdout.write("|Author : $name\n");
    printDepth(depth);
    stdout.write("|\n");
    printDepth(depth);
    stdout.write("|id     : ${max3(id)}     Time: $dTime");
  }

  @override
  String toString() {
    if( id == "non") {
      return '';
    }

    String max3(String v) => v.length > 3? v.substring(0,3) : v.substring(0, v.length);
    DateTime dTime = DateTime.fromMillisecondsSinceEpoch(createdAt *1000);
    if( createdAt == 0) {
      print("createdAt == 0 for event $content");
    }
    return '\n-------+-------------\nAuthor : ${max3(pubkey)}\nMessage: $content\n\nid     : ${max3(id)}     Time: $dTime     Kind: $kind';
  }
}

class Event {
  String event;
  String id;
  EventData eventData;
  String originalJson;
  List<String> seenOnRelays;

  Event(this.event, this.id, this.eventData, this.seenOnRelays, this.originalJson);

  factory Event.fromJson(String d, String relay) {
    dynamic json = jsonDecode(d);
    if( json.length < 3) {
      String e = "";
      e = json.length > 1? json[0]: "";
      return Event(e,"",EventData("non","", 0, 0, "", "", [], [], []), [relay], "[json]");
    }
    return Event(json[0] as String, json[1] as String,  EventData.fromJson(json[2]), [relay], d );
  }

  void printEvent(int depth) {
    eventData.printEventData(depth);
    //stdout.write("\n$originalJson \n");
  }

  @override 
  String toString() {
    return '$eventData     Seen on: ${seenOnRelays[0]}\n';
  }
}

class Tree {
  Event e;
  List<Tree> children;
  Tree(this.e, this.children);

  // @method create top level Tree from events. 
  // first create a map. then add all top trees to the final list/ChildTrees. then add children to it.
  factory Tree.fromEvents(List<Event> events) {
    stdout.write("in factory fromEvents list. number of events: ${events.length}\n");

    // create a map from list of events
    Map<String, Tree> m = {};
    events.forEach((element) { m[element.eventData.id] = Tree(element, []); });

    List<String>  processed = [];

    m.forEach((key, value) {
      bool alreadyProcessed = false;
      for( int i = 0; i < processed.length; i++) {
        if( processed[i] == key) {
          alreadyProcessed = true;
          break;
        }
      }

      if( !alreadyProcessed) {
        if( !value.e.eventData.eTagsRest.isNotEmpty ) {
          // in case this node is a parent, then move it to processed()
          processed.add(key);
        } else {
          // is not a parent, find its parent and then add this element to that parent Tree
          stdout.write("added to parent a child\n");
          String id = key;
          String parentId = value.e.eventData.getParent();
          m[parentId]?.addChildNode(value);
          processed.add(key);
        }
      } else { // entry already exists
        // do nothing
      }
    });

    // add parent trees as top level child trees of this tree
    List<Tree>  childTrees = [];
    for( var value in m.values) {
        if( !value.e.eventData.eTagsRest.isNotEmpty) {  // if its a parent
            childTrees.add(value);
        }
    }

    stdout.write("Ending:  factory fromEvents list. number of processed events: ${processed.length}\n");
    return Tree( events[0], childTrees); // TODO remove events[0]
  }

  void addChild(Event child) {
    Tree node;
    node = Tree(child, []);
    children.add(node);
  }

  void addChildNode(Tree node) {
    children.add(node);
  }

  void printTree(int depth, bool onlyPrintChildren) {
    children.sort(ascendingTimeTree);
    if( !onlyPrintChildren) {
      e.printEvent(depth);
    } else {
      depth = depth - 1;
    }

    for( int i = 0; i < children.length; i++) {
      stdout.write("\n");  
      printDepth(depth+1);
      if(!onlyPrintChildren) {
        stdout.write("|\n");
      } else {
        stdout.write("\n\n\n");
      }
      children[i].printTree(depth+1, false);
    }
  }
}

List<String> getpTags(List<Event> events) {
  List<String> pTags = [];
  for(int i = 0; i < events.length; i++) {
    pTags.addAll(events[i].eventData.pTags);
  }
  return pTags;
}

int ascendingTime(Event a, Event b) {
  if(a.eventData.createdAt < b.eventData.createdAt) {
    //print( 'ascendingTime : comparing two ${a.eventData.createdAt} and   ${b.eventData.createdAt}'); 
    return 0;
  }
  return 1;
}

int ascendingTimeTree(Tree a, Tree b) {
  if(a.e.eventData.createdAt < b.e.eventData.createdAt) {
    //print( 'ascendingTimeTree : comparing two ${a.e.eventData.createdAt} and   ${b.e.eventData.createdAt}'); 
    return 0;
  }
  return 1;
}

void printEvents(List<Event> events) {
    events.sort(ascendingTime);
    for( int i = 0; i < events.length; i++) {
      if( events[i].eventData.kind == 1) {
        print('${events[i]}');
      }
    }
}

/* 
kind 0 event
{
  "id": "63de3e2fe397fedef9d8f1937e8c7f73727bd6410d2e7578eb348d4ee059feaf",
  "pubkey": "004db7605cfeba09b15625deb77c9369029f370591d68231b7c4dfd43f8f6f4f",
  "created_at": 1659944329,
  "kind": 0,
  "tags": [],
  "content": "{\"name\":\"IrredeemablePussy@minds.com\",\"about\":\"\",\"picture\":\"https://www.minds.com/icon/742483671239368719/medium/1502397901/1659944329/1659944329\"}",
  "sig": "c500f7f8e27c3d1a41ed196931f66253cdd42dbb1e53b15fd1916da5c261b4d0e06d0008b39016775b3be56e6397c8d747d98174106f04c5874650fbe9d930b0"
}


reply/root example for e tag
{
  "id": "4019debf44a087b973b7d8776e7ce74ee84a15e9c3dbed0b60dfdec23d170911",
  "pubkey": "2ef93f01cd2493e04235a6b87b10d3c4a74e2a7eb7c3caf168268f6af73314b5",
  "created_at": 1659210144,
  "kind": 1,
  "tags": [
    [
      "e",
      "0ddebf828647920417deb00cc9de70a83db5b5c414466f684a5cbe7f02723243",
      "",
      "root"
    ],
    [
      "e",
      "f68f0299f3a3204638337e6f7edf1a6653066a8d8a2bc74c4ab6ebe92a9c4130",
      "",
      "reply"
    ],
*/


/*  
NIP 02
{
  "kind": 3,
  "tags": [
    ["p", "91cf9..4e5ca", "wss://alicerelay.com/", "alice"],
    ["p", "14aeb..8dad4", "wss://bobrelay.com/nostr", "bob"],
    ["p", "612ae..e610f", "ws://carolrelay.com/ws", "carol"]
  ],
  "content": "",
  ...other fields


Example Event returned
[
  "EVENT",
  "latest",
  {
    "id": "5e4ca472540c567ba877ab232fa77c0801f4b2121756ed21d827e749b5074ac7",
    "pubkey": "47bae3a008414e24b4d91c8c170f7fce777dedc6780a462d010761dca6482327",
    "created_at": 1657316002,
    "kind": 1,
    "tags": [
      [
        "p",
        "80482e60178c2ce996da6d67577f56a2b2c47ccb1c84c81f2b7960637cb71b78",
        "wss://relay.damus.io"
      ],
      [
        "e",
        "241f1108b3616eb4b3cfb9fdbab29d7f8d291fda9db84a79f2491271e2f6122e"
      ],
      [
        "e",
        "b3349c4de2ff7a672c564e6fd147bc2d5dd71b525f96f35f8ede75138136c867",
        "wss://nostr-pub.wellorder.net"
      ]
    ],
    "content": "Not even surprised it's a thing https://coinmarketcap.com/currencies/lol/",
    "sig": "abebbc96a8a922f06ca2773c59521d03b6a8dd5597ae5654afc2d49e03a1e9c193729ff60473f837edc526e41c94f3de8a328c20bf9cff5353cb9c409a982461"
  }
]


  factory EventData.fromStr(String str) {
    var json = jsonDecode(str);
    return EventData(json['id'] as String, json['pubkey'] as String, json['content'] as String);
  }
 */