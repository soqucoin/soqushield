// SoquShield Field Manual — the in-app user guide content.
//
// Written for the non-technical holder. Every article is task-shaped ("do
// this, in this order") and quotes the app's real on-screen labels so a
// reader can match the words in front of them. Plain voice, no marketing
// filler, no dates.
//
// Content lives here as plain data so the guide works offline and ships
// versioned with the app. The renderer is lib/screens/guide/.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// One block of an article: an optional small heading, an optional paragraph,
/// an optional numbered step list, and an optional NOTE callout.
class GuideSection {
  final String? heading;
  final String? body;
  final List<String> steps;
  final String? note;
  const GuideSection({this.heading, this.body, this.steps = const [], this.note});
}

class GuideArticle {
  final String id;
  final String title;
  final String tagline;
  final IconData icon;
  final List<GuideSection> sections;
  const GuideArticle({
    required this.id,
    required this.title,
    required this.tagline,
    required this.icon,
    required this.sections,
  });
}

class GuideCategory {
  final String label;
  final List<GuideArticle> articles;
  const GuideCategory({required this.label, required this.articles});
}

GuideArticle? guideArticleById(String id) {
  for (final c in guideCategories) {
    for (final a in c.articles) {
      if (a.id == id) return a;
    }
  }
  return null;
}

// A getter (not a const/final list): the screen-capture section under
// STAY SAFE is platform-conditional, and a top-level final would freeze
// the platform choice at first access.
List<GuideCategory> get guideCategories => [
  // ───────────────────────── GETTING STARTED ─────────────────────────
  GuideCategory(label: 'GETTING STARTED', articles: [
    GuideArticle(
      id: 'create-wallet',
      title: 'Create your wallet',
      tagline: 'From first open to a working wallet in about a minute.',
      icon: Icons.bolt_outlined,
      sections: [
        GuideSection(
          body:
              'SoquShield is self-custodial. That means the keys to your money are created on your phone and stay on your phone. Nobody else holds them, including us.',
        ),
        GuideSection(
          steps: [
            'On the welcome screen, tap CREATE A WALLET.',
            'Give the wallet a name. Anything works, "Personal" is fine. Only you see it.',
            'Leave "Unlock with Face ID / Touch ID" on if your phone supports it. It protects the app without slowing you down.',
            'Tap ACTIVATE. The app generates your post-quantum keys on the device. This takes a few seconds.',
            'You will land on the Recovery Phrase screen next. Do not skip it. See "Your recovery phrase" in this manual.',
          ],
        ),
        GuideSection(
          note:
              'A new wallet is created on Mainnet, so its address begins sq1. That is the address that receives SOQ on the real network.',
        ),
      ],
    ),
    GuideArticle(
      id: 'seed-phrase',
      title: 'Your recovery phrase',
      tagline: 'The 24 words that ARE your wallet. Treat them like cash.',
      icon: Icons.key_outlined,
      sections: [
        GuideSection(
          body:
              'When you create a wallet, the app shows you 24 words and asks you to write them down in order. Those words are the master copy of your keys. If your phone is lost, broken, or wiped, the 24 words are the only way to get your money back. No company can restore them for you.',
        ),
        GuideSection(
          heading: 'Do',
          steps: [
            'Write the words on paper, in order, and check your spelling.',
            'Store the paper somewhere you would store cash or a passport.',
            'Consider a second copy in a different place, like a safe deposit box.',
          ],
        ),
        GuideSection(
          heading: 'Never',
          steps: [
            'Never type the words into a website, email, or chat message.',
            'Never share them with anyone. Support will never ask for them. Anyone who does ask is trying to rob you.',
            'Never store them as a screenshot or photo. Phones sync photos to the cloud.',
          ],
        ),
        GuideSection(
          heading: 'View them again',
          body:
              'Settings, then "Recovery phrase" under BACKUP & KEYS. The app asks you to unlock with Face ID or your passcode first, and reminds you to make sure no one is watching.',
        ),
        GuideSection(
          heading: 'An encrypted file as well',
          body:
              'Settings, then "Encrypted backup", writes your wallet into a password-protected file you can keep in your own cloud drive. The file is useless without the password, and the password is useless without the file. Keep both, apart from each other.',
        ),
        GuideSection(
          note:
              'The "Copy All" button auto-clears your clipboard after 60 seconds, but writing on paper is still the safer habit.',
        ),
      ],
    ),
    GuideArticle(
      id: 'restore-wallet',
      title: 'Restore a wallet',
      tagline: 'Moving to a new phone, or recovering after a loss.',
      icon: Icons.restore_outlined,
      sections: [
        GuideSection(
          steps: [
            'On the welcome screen, tap I ALREADY HAVE A WALLET.',
            'Enter your 24 recovery words in order, or paste all 24 at once.',
            'The app rebuilds your keys on this device. The same 24 words always give the same address, here and in the web console.',
          ],
        ),
        GuideSection(
          body:
              'Your balance is not stored inside the old phone. It lives on the Soqucoin network, and the 24 words prove it is yours. That is why restoring works from any device.',
        ),
        GuideSection(
          note:
              'A recovered wallet opens on Mainnet. If your coins are on Stagenet, switch the network in Settings; the same 24 words give your stagenet address there. After moving to a new phone, consider wiping the old one: Settings, DANGER ZONE, "Wipe wallet". Two phones holding the same keys is two places they can be stolen from.',
        ),
      ],
    ),
    GuideArticle(
      id: 'networks',
      title: 'Mainnet and Stagenet',
      tagline: 'Which network you are on, and what opens when.',
      icon: Icons.lan_outlined,
      sections: [
        GuideSection(
          body:
              'Mainnet is the real Soqucoin network. A new wallet is created on it, and its address begins sq1. Until mainnet launches, the app shows your address and reads OFFLINE; your balance and sending open at mainnet launch, with no update needed.',
        ),
        GuideSection(
          heading: 'Stagenet',
          body:
              'Stagenet is the public test network. It behaves like the real one, but its coins are test coins with no monetary value. Switch to it in Settings under NETWORK to practise. A stagenet address begins ssq1 and cannot receive anything on mainnet.',
        ),
        GuideSection(
          note:
              'The badge in the top right corner of the wallet always names the network you are on. Check it before you share an address.',
        ),
      ],
    ),
  ]),

  // ───────────────────────── EVERYDAY USE ─────────────────────────
  GuideCategory(label: 'EVERYDAY USE', articles: [
    GuideArticle(
      id: 'wallet',
      title: 'Reading the Wallet screen',
      tagline: 'What every number and label on the home screen is telling you.',
      icon: Icons.account_balance_wallet_outlined,
      sections: [
        GuideSection(
          body:
              'The Wallet tab is your main balance view. The figure at the top is your custody line: YOUR KEY on this device, connected to the SOQ L1 network, with the live block number on the right. When the status line reads LIVE, you are connected.',
        ),
        GuideSection(
          heading: 'The pieces',
          steps: [
            'HOLDINGS · SOQ (tSOQ on Stagenet) is your total. Tap it to mask the number when someone is looking over your shoulder.',
            'A "+n SETTLING" line means coins are on their way to you and waiting for network confirmation.',
            'SEND and RECEIVE are the two actions.',
            'Your address is under ASSETS. Tap it to copy.',
            'NETWORK shows the latest block and the network\'s mining power. Tap it to open the Network tab.',
          ],
        ),
        GuideSection(
          note:
              'If you see a "BACK UP YOUR RECOVERY PHRASE" banner, the app is reminding you that your 24 words are not confirmed saved. Do that before anything else.',
        ),
      ],
    ),
    GuideArticle(
      id: 'receive',
      title: 'Receive SOQ',
      tagline: 'Share your address by QR code or as text.',
      icon: Icons.qr_code_2_outlined,
      sections: [
        GuideSection(
          steps: [
            'From the Wallet tab, tap RECEIVE.',
            'Show the QR code to the sender. It contains your address and nothing else.',
            'Or tap COPY ADDRESS and send the address any way you like.',
            'Or tap SHARE ADDRESS to hand it to another app on your phone, such as a message.',
          ],
        ),
        GuideSection(
          body:
              'Incoming coins appear in your history right away and count as settled after network confirmation, usually within a couple of minutes.',
        ),
        GuideSection(
          note:
              'This wallet has one address. Anyone can send to it; only your 24 words can spend from it.',
        ),
      ],
    ),
    GuideArticle(
      id: 'send',
      title: 'Send SOQ',
      tagline: 'Addresses, fees, and what the signing screen means.',
      icon: Icons.north_east,
      sections: [
        GuideSection(
          steps: [
            'From the Wallet tab, tap SEND.',
            'Enter the amount.',
            'Paste the recipient\'s address. The app checks that it belongs to the network you are on.',
            'Review the FEE line. The fee pays the network, not us.',
            'Tap SEND SOQ (SEND TSOQ on Stagenet) and confirm with Face ID or your passcode.',
          ],
        ),
        GuideSection(
          heading: 'The signing screen',
          body:
              'You will briefly see QUANTUM-SIGNING with a "DO NOT CLOSE THE APP" warning. Your phone is building the post-quantum signature. It takes a moment. Then the SENT screen shows the amount and a receipt hash you can tap to copy.',
        ),
        GuideSection(
          heading: 'Before you send, know this',
          body:
              'Transactions cannot be reversed. If you send to a wrong address, nobody can pull it back, so check the first and last characters of the address before confirming.',
        ),
        GuideSection(
          note:
              'On Mainnet, sending opens at mainnet launch. Until then the balance reads 0 and the app refuses to send, by design.',
        ),
      ],
    ),
    GuideArticle(
      id: 'activity',
      title: 'Your history',
      tagline: 'Reading the Activity list.',
      icon: Icons.receipt_long_outlined,
      sections: [
        GuideSection(
          body:
              'The Activity tab lists everything the wallet has done, newest first, grouped under TODAY, YESTERDAY, and dates. Sent and Received are your SOQ transfers. Tap a row to copy its receipt hash.',
        ),
        GuideSection(
          note:
              'After restoring from your 24 words, the history is rebuilt from the network over a few minutes.',
        ),
      ],
    ),
    GuideArticle(
      id: 'network',
      title: 'The Network screen',
      tagline: 'The weather of the chain and the pool, read live.',
      icon: Icons.sensors_outlined,
      sections: [
        GuideSection(
          body:
              'The Network tab reads what the chain and the pool report right now, the way a weather app reads the sky. Every figure comes from the node you are connected to or from the pool\'s public statistics; nothing on this screen is an account, a balance or a key.',
        ),
        GuideSection(
          heading: 'The block clock',
          body:
              'The ring fills over the sixty seconds the network aims to take between blocks. Past the full ring it continues in a dimmer tone: the next block is running late against that target, which happens often and means nothing is wrong. A new block runs a light around the ring and starts it again.',
        ),
        GuideSection(
          heading: 'Under the clock',
          body:
              'One sentence says in plain words how the chain is doing against its sixty-second target, and whether the pool is operational. Below it sit three cards: CHAIN, EMISSION and SOQUPOOL. Each shows a one-line summary. Tap a card to open its full figures, and tap it again to close it.',
        ),
        GuideSection(
          heading: 'The figures, card by card',
          steps: [
            'CHAIN: HASHRATE is the node\'s estimate of the whole network\'s mining power. DIFFICULTY is how hard a block is to find right now. MEMPOOL counts transactions waiting for a block. PEERS is how many other nodes yours is talking to.',
            'EMISSION: BLOCK REWARD is what the block at this height pays. NEXT CHANGE is what the reward becomes, at which height, and how long the chain takes to get there at sixty-second blocks.',
            'SOQUPOOL: the pool\'s own published figures, with its status beside the name: its hashrate, how many miners and workers are connected, blocks found in the last day, luck, the effort of the current round, the next payout time, the fee and the regions. The pool pays its members to their own addresses; the app only reads what the pool publishes.',
            'LATEST BLOCKS, inside the SOQUPOOL card, lists the blocks the pool found most recently.',
          ],
        ),
        GuideSection(
          note:
              'On Mainnet before launch the node does not answer yet, so the clock reads offline and the SOQUPOOL card waits. Both come alive at mainnet launch with no update needed.',
        ),
      ],
    ),
  ]),

  // ───────────────────────── STAY SAFE ─────────────────────────
  GuideCategory(label: 'STAY SAFE', articles: [
    GuideArticle(
      id: 'safety',
      title: 'Security guidelines',
      tagline: 'The habits that keep a self-custody wallet safe.',
      icon: Icons.verified_user_outlined,
      sections: [
        GuideSection(
          heading: 'The one rule that matters most',
          body:
              'Your 24-word recovery phrase is the wallet. Anyone who has the words has your money, from anywhere in the world, with no way to undo it. Support will never ask for them. No giveaway, airdrop, "validation", or "sync" ever needs them. Every message that asks is a scam, without exception.',
        ),
        GuideSection(
          heading: 'Good habits',
          steps: [
            'Keep "Biometric lock" and "Lock on background" on in Settings.',
            'Verify addresses before sending. Check the first and last characters.',
            'Send a small test amount first when paying someone new.',
            'Update the app when updates ship. Security fixes ride along.',
            'If a deal or message pressures you to act fast, that pressure is the red flag. Real ones can wait.',
          ],
        ),
        if (defaultTargetPlatform == TargetPlatform.android)
          const GuideSection(
            heading: 'Why screenshots look black',
            body:
                'If you try to screenshot or screen-record the app, the capture comes out black. That is deliberate. It stops malware and screen-sharing scams from photographing your balance or your recovery phrase.',
          )
        else
          const GuideSection(
            heading: 'How the app hides from prying screens',
            body:
                'When you switch apps, SoquShield blurs its content in the app switcher, so nothing on screen can be read from a preview. Screenshots still work on iOS. Treat them with care, and never screenshot your recovery phrase.',
          ),
        GuideSection(
          heading: 'Wiping this device',
          body:
              'Settings, DANGER ZONE, "Wipe wallet" deletes everything from this phone. Only do it if your 24 words are written down, because after a wipe they are the only way back in.',
        ),
      ],
    ),
    GuideArticle(
      id: 'glossary',
      title: 'Plain words for the technical parts',
      tagline: 'Every term the app uses, translated.',
      icon: Icons.menu_book_outlined,
      sections: [
        GuideSection(
          heading: 'SOQ',
          body: 'The coin of the Soqucoin network. What the Wallet tab counts.',
        ),
        GuideSection(
          heading: 'Shors',
          body:
              'The smallest slice of a SOQ, like cents to a dollar. One SOQ is 100 million shors. Named after the quantum algorithm Soqucoin is built to resist.',
        ),
        GuideSection(
          heading: 'Post-quantum / ML-DSA-44',
          body:
              'Future quantum computers could break the signatures that protect most cryptocurrencies today. Soqucoin signs with ML-DSA-44, a newer scheme standardized by the US government (FIPS 204) that quantum computers cannot break. That is the "QUANTUM-SIGNED" badge you see around the app.',
        ),
        GuideSection(
          heading: 'Self-custody',
          body:
              'You hold your own keys, on your own device. The opposite of an exchange account, where a company holds the keys and you hold a promise.',
        ),
        GuideSection(
          heading: 'Confirmation',
          body:
              'The network sealing your transaction into its permanent record. Each confirmation makes it more final. A couple of minutes covers everyday payments.',
        ),
        GuideSection(
          heading: 'Fee',
          body:
              'A small amount paid to the network with each on-chain transaction. It pays the machines that secure the network. The app shows it before you confirm.',
        ),
        GuideSection(
          heading: 'pSOQ',
          body:
              'The Solana token that came before SOQ. It converted to SOQ once, through a one-time window that has closed. There is no bridge, and nobody from the project will ever ask you to send pSOQ anywhere or connect a wallet to a site.',
        ),
        GuideSection(
          heading: 'Mainnet',
          body: 'The real Soqucoin network. Addresses begin sq1.',
        ),
        GuideSection(
          heading: 'Stagenet',
          body: 'The public test network. Real software, practice money. Addresses begin ssq1.',
        ),
      ],
    ),
  ]),
];
