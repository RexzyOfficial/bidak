#!/usr/bin/env python3
"""Konversi Polyglot .bin -> TSV (fen4 <TAB> uci:bobot uci:bobot ...) untuk Bidak."""
import collections
import sys

import chess
import chess.polyglot

BIN = sys.argv[1] if len(sys.argv) > 1 else "tools/gm2001.bin"
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/book/gm2001.tsv"
MAX_PLY = 40
MIN_WEIGHT = 1


def key4(board):
    # en_passant="fen": kotak ep selalu ditulis setelah dorongan 2 kotak,
    # sama seperti toFen() di app.
    return " ".join(board.fen(en_passant="fen").split(" ")[:4])


def fix_castling(board, move):
    # Polyglot menulis rokade sebagai "raja makan benteng sendiri" (e1h1).
    piece = board.piece_at(move.from_square)
    if piece is not None and piece.piece_type == chess.KING:
        target = board.piece_at(move.to_square)
        if (target is not None and target.piece_type == chess.ROOK
                and target.color == piece.color):
            kingside = (chess.square_file(move.to_square)
                        > chess.square_file(move.from_square))
            to_sq = chess.square(6 if kingside else 2,
                                 chess.square_rank(move.from_square))
            return chess.Move(move.from_square, to_sq)
    return move


def moves_at(reader, board):
    out = []
    for e in reader.find_all(board, minimum_weight=MIN_WEIGHT):
        m = fix_castling(board, e.move)
        if board.is_legal(m):
            out.append((m, e.weight))
    return out


def main():
    start = chess.Board()
    table = {}
    seen = {key4(start)}
    queue = collections.deque([(start, 0)])
    max_ply = 0

    with chess.polyglot.open_reader(BIN) as reader:
        first = moves_at(reader, start)
        if not first:
            sys.exit("GAGAL: tidak ada langkah dari posisi awal. File bukan Polyglot valid?")
        print("Langkah pertama di book:")
        for m, w in sorted(first, key=lambda x: -x[1]):
            print("  %s  bobot %d" % (m.uci(), w))

        while queue:
            board, ply = queue.popleft()
            entries = moves_at(reader, board)
            if not entries:
                continue
            table[key4(board)] = [(m.uci(), w) for m, w in entries]
            max_ply = max(max_ply, ply + 1)
            if ply + 1 >= MAX_PLY:
                continue
            for m, _ in entries:
                child = board.copy(stack=False)
                child.push(m)
                ck = key4(child)
                if ck not in seen:
                    seen.add(ck)
                    queue.append((child, ply + 1))

    with open(OUT, "w") as f:
        for k in sorted(table):
            f.write("%s\t%s\n" % (k, " ".join("%s:%d" % (u, w) for u, w in table[k])))
    print("Posisi: %d, kedalaman maks: %d ply -> %s" % (len(table), max_ply, OUT))


main()
