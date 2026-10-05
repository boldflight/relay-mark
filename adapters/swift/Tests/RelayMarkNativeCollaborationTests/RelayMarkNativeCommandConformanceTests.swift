import Foundation
import XCTest
import RelayMarkSwift
@testable import RelayMarkNativeCollaboration
@MainActor final class RelayMarkNativeCommandConformanceTests:XCTestCase {
 func testNativeRichCommandsUseCanonicalAttributeItemOrderAndExactWitness() throws {
  let owner=UUID(uuidString:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
  for (ordinal,kind) in ["media","control","atom"].enumerated() {
   let doc=RelayMarkNativeDocument(historyOwnerID:owner)
   let ast=try RelayMarkSourceCodec.parseDocument("Before\n\nAfter",namespace:"native-command-proof")
   _ = try doc.initializeDocument(authoredAST:ast)
   let root=try JSONSerialization.jsonObject(with:doc.snapshot()) as! [String:Any]
   let nodes=root["children"] as! [[String:Any]],previous=(nodes[0]["attributes"] as! [String:Any])["relaymarkId"] as! String,next=(nodes[1]["attributes"] as! [String:Any])["relaymarkId"] as! String
   let baseline=try doc.encodeUpdate(),before=try JSONSerialization.jsonObject(with:doc.captureIdentitySnapshot())
   let beforeFootprint=try JSONSerialization.jsonObject(with:doc.captureUpdateFootprint(Data([0,0]))) as! [String:Any]
   let observation=try doc.captureContentEditObservation(),id=UUID(uuidString:"88888888-8888-4888-8888-88888888888\(ordinal)")!
   var change:RelayMarkNativeRichEditing.Change?
   _ = try doc.performOwnedCommand(operationID:id) {
    switch kind {
    case "media": change=try RelayMarkNativeMediaMutation.insert(document:doc,atRootIndex:1,expectedPreviousID:previous,expectedNextID:next,block:.init(id:"bddddddddddd44ddd8ddddddddddddddd",kind:.image,source:"https://example.com/diagram.png",alt:"Diagram",title:"Rich image",width:320,height:180))
    case "control":change=try RelayMarkNativePaperControlMutation.insert(document:doc,atRootIndex:1,expectedPreviousID:previous,expectedNextID:next,block:.init(id:"bddddddddddd44ddd8ddddddddddddddd",control:.button,authored:["label":"Next","kind":"anchor","target":"next"]))
    default:change=try RelayMarkNativeInlineAtomMutation.insert(document:doc,blockID:previous,childIndex:0,utf16Offset:3,expectedLeafText:"Before",atom:.init(kind:.relayTag,attributes:["id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","name":"followup","source":"[[Tag: bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb | #followup]]"]))
    }
    return change!.update
   }
   let actual=try XCTUnwrap(change),group=try doc.ownedCommandGroup(operationID:id)
   let witness=try JSONSerialization.jsonObject(with:doc.buildContentEditWitness(observation,steps:actual.steps,update:actual.update)) as! [String:Any]
   let operation:[String:Any]=["kind":"content_edit","steps":try JSONSerialization.jsonObject(with:actual.steps),"copies":witness["proven_copies"] ?? [],"group":["owner_id":group.ownerID.uuidString.lowercased(),"reference":group.reference.uuidString.lowercased(),"operation_ids":group.operationIDs.map{$0.uuidString.lowercased()}]]
   let footprint=try JSONSerialization.jsonObject(with:doc.captureUpdateFootprint(actual.update)) as! [String:Any]
   let keys=(footprint["structs"] as! [[String:Any]]).compactMap{$0["key"] as? String}
   switch kind {
   case "media":XCTAssertEqual(keys,["relaymarkId","src","alt","title","width","height"])
   case "control":XCTAssertEqual(keys,["relaymarkId","label","kind","target"])
   default:XCTAssertEqual(keys,["id","name","source"])
   }
   XCTAssertEqual((witness["text_items"] as! [String:Any])["runs"] as? [[String:Int]],[])
   let after=try JSONSerialization.jsonObject(with:doc.captureIdentitySnapshot())
   let old=(beforeFootprint["state_vector"] as! [[String:Any]]).reduce(into:[Int:Int]()){$0[$1["client"] as! Int]=$1["clock"] as! Int}
   let writers=Set((footprint["structs"] as! [[String:Any]]).compactMap { r -> Int? in let item=r["item"] as! [String:Int];return item["clock"]!+(r["count"] as! Int)>(old[item["client"]!] ?? 0) ? item["client"]! : nil })
   XCTAssertEqual(writers.count,1)
   let fixture:[String:Any]=["description":"Actual native \(kind) command; retained original state, owned group, Steps and original full footprint","transaction_id":id.uuidString.lowercased(),"sender_state_base64":baseline.base64EncodedString(),"current_state_base64":baseline.base64EncodedString(),"before_snapshot_base64":actual.beforeSnapshot.base64EncodedString(),"update_base64":actual.update.base64EncodedString(),"writer_client":writers.first!,"operation":operation,"text_items":witness["text_items"]!,"footprint":footprint,"evidence":["sender_before_snapshot":before,"sender_after_snapshot":after,"before_snapshot":before,"after_snapshot":after,"before_state_vector":beforeFootprint["state_vector"]!,"operation":operation,"footprint":footprint]]
   if let directory=ProcessInfo.processInfo.environment["RELAY_NATIVE_COMMAND_FIXTURE_OUTPUT"] {
    try JSONSerialization.data(withJSONObject:fixture,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:directory).appendingPathComponent("content-edit-native-\(kind).json"))
   }
  }
 }
}
