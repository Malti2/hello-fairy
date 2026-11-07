from hellofairy import protocol as P


def test_known_vectors():
    assert P.power_packet(True).hex() == "aa020101ae"
    assert P.power_packet(False).hex() == "aa020100ad"
    assert P.playback_packets("picture", "left", 20, 100)[0].hex() == "aad00403641401fa"
    a, b = P.playback_packets("animation", "breathe", 30, 75)
    assert (a.hex(), b.hex()) == ("aad004014b1e02ea", "aadc010188")
    assert P.build_packet(0xD0, [0, 0x64, 0x64, 3]).hex() == P.d0_packet(3).hex()


def test_frame_packets_shape():
    frame = [P.PIXEL_OFF] * 400
    assert [len(p) for p in P.frame_to_da_packets(frame)] == [242] * 5 + [20]


def test_column_major():
    frame = [P.PIXEL_OFF] * 400
    frame[1 * 20 + 0] = 60  # row 1, col 0 -> index 0*20+1 = 1
    pkt = P.frame_to_da_packets(frame)[0]
    assert pkt[4:7] == bytes([0, 0, P.PIXEL_OFF]) and pkt[7:10] == bytes([0, 1, 60])


def test_sequence_two_pictures():
    f = [0] * 400
    assert len(P.two_picture_sequence([f, f])) == 1 + 2 * (1 + 6 + 1) + 1 + 2
