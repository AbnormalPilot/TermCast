import Testing
import Foundation
import NIOCore
import NIOEmbedded
@testable import TermCast

@Suite("SessionBroadcaster")
struct SessionBroadcasterTests {
    @Test("Initial client count is zero")
    func initialClientCountIsZero() async {
        let bc = SessionBroadcaster()
        let count = await bc.clientCount
        #expect(count == 0)
    }

    @Test("Add channel increments count")
    func addChannelIncrementsCount() async {
        let bc = SessionBroadcaster()
        let channel = EmbeddedChannel()
        await bc.add(channel: channel)
        #expect(await bc.clientCount == 1)
    }

    @Test("Remove channel decrements count")
    func removeChannelDecrementsCount() async {
        let bc = SessionBroadcaster()
        let channel = EmbeddedChannel()
        await bc.add(channel: channel)
        await bc.remove(channel: channel)
        #expect(await bc.clientCount == 0)
    }

    @Test("Adding same channel twice counts as one")
    func addSameChannelTwiceCountsAsOne() async {
        let bc = SessionBroadcaster()
        let channel = EmbeddedChannel()
        await bc.add(channel: channel)
        await bc.add(channel: channel)
        #expect(await bc.clientCount == 1)
    }

    @Test("Remove non-existent channel is a no-op")
    func removeNonExistentIsNoop() async {
        let bc = SessionBroadcaster()
        let channel = EmbeddedChannel()
        await bc.remove(channel: channel)
        #expect(await bc.clientCount == 0)
    }

    @Test("Three channels then remove one")
    func threeChannelsThenRemoveOne() async {
        let bc = SessionBroadcaster()
        let ch1 = EmbeddedChannel()
        let ch2 = EmbeddedChannel()
        let ch3 = EmbeddedChannel()
        await bc.add(channel: ch1)
        await bc.add(channel: ch2)
        await bc.add(channel: ch3)
        #expect(await bc.clientCount == 3)
        await bc.remove(channel: ch2)
        #expect(await bc.clientCount == 2)
    }
}
