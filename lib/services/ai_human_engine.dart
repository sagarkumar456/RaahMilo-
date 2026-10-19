/// Dedicated Human-like Conversational AI Engine for RaahMilo
/// Provides warm, empathetic, and human-like natural conversation in Hindi, Hinglish, and English.
class AiHumanEngine {
  /// Generate a natural, caring, and context-aware human response
  static String generateHumanResponse(
    String input, {
    String? ticketId,
    bool useHindi = false,
  }) {
    final lower = input.trim().toLowerCase();

    // 1. If an issue was just reported and ticket created
    if (ticketId != null) {
      if (useHindi) {
        return 'Arey bhai, aap bilkul tension mat lijiye! Maine aapki samasya note karke seedhe Support Desk ko urgent alert bhej diya hai. 🛡️\n\n'
            '📋 Ticket Number: #$ticketId\n'
            'Status: Active • Support Team Assigned\n\n'
            'Humari security team ispe turant action le rahi hai aur jald se jald aapse sampark karegi. Tab tak aap gaadi ka status Live Map par dekhte rahein!';
      } else {
        return 'Please don\'t worry at all! I have immediately escalated your issue and forwarded an urgent priority alert to our Support Operations Desk. 🛡️\n\n'
            '📋 Ticket ID: #$ticketId\n'
            'Status: Active • Assigned to Support Desk\n\n'
            'Our engineering & security team is reviewing this right now and will get in touch with you shortly. You can monitor your vehicle\'s live position on the map in the meantime!';
      }
    }

    // 2. Greetings & Friendly Chit-chat
    if (_matches(lower, ['kaise ho', 'kya hal', 'kya haal', 'hello', 'hi', 'hey', 'namaste', 'pranam', 'bhai', 'bro', 'good morning', 'good evening'])) {
      if (useHindi) {
        return 'Namaste bhai! 👋 Main bilkul badhiya hoon, aap bataiye aap kaise hain? Main aapka dost RaahMilo Assistant hoon.\n\nAaj aapki gaadi ya bike ki security me main kya madad kar sakta hoon? Koi bhi doubt ho toh bina jhijhak poochhiye!';
      } else {
        return 'Hey there! 👋 I\'m doing great, thank you so much for asking! How are you doing today?\n\nI\'m your personal RaahMilo security companion. How can I help keep your bike or car secure today? Feel free to ask me anything!';
      }
    }

    // 3. Identity: "Who are you? Are you human or AI?"
    if (_matches(lower, ['kaun ho', 'who are you', 'tum kon ho', 'kya ho', 'robot', 'bot ho', 'human ho'])) {
      if (useHindi) {
        return 'Main RaahMilo ka smart security assistant hoon, par main aapse bilkul ek sachhe dost ki tarah baat karta hoon! 😊\n\nMera kaam hai aapki gaadi ko chori hone se bachana, live GPS dikhana, aur agar koi samasya aaye toh turant support team ko alert bhejna.';
      } else {
        return 'I am your RaahMilo Smart Security Assistant, designed to chat with you just like a friendly human companion! 😊\n\nMy mission is to safeguard your vehicle against theft, provide real-time GPS tracking, and instantly alert our support team whenever you need assistance.';
      }
    }

    // 4. Theft Fear & Anxiety: "Chori ho sakti hai kya? Dar lag raha hai"
    if (_matches(lower, ['chori ho sakti', 'chori ka dar', 'dar lag raha', 'kho jayegi', 'safe hai', 'surakshit', 'stolen', 'theft fear', 'is it safe'])) {
      if (useHindi) {
        return 'Bhai, bilkul tension mat lo! RaahMilo ka Anti-Theft shield isi dar ko khatam karne ke liye banaya gaya hai. 🛡️\n\n'
            'Jab bhi aap gadi kahin park karein:\n'
            '1️⃣ Anti-Theft tab me jakar "ARM VEHICLE" daba dijiye.\n'
            '2️⃣ Ab agar koi bhi aapki gaadi ko 1 meter bhi hilaayega ya chori karne ki koshish karega, to aapke phone par zordar siren bajega aur turant alert aayega!\n\n'
            'Aap aaram se so sakte hain, RaahMilo aapki gaadi ki pehredari kar raha hai.';
      } else {
        return 'Hey, please take a deep breath and relax! RaahMilo\'s Anti-Theft Shield was specifically built to protect you from this fear. 🛡️\n\n'
            'Whenever you park your vehicle:\n'
            '1️⃣ Head over to the Anti-Theft screen and tap "ARM VEHICLE".\n'
            '2️⃣ If anyone attempts to move or tamper with your vehicle by even 1 meter, your phone will sound a loud alarm siren and dispatch an instant high-priority alert!\n\n'
            'Rest easy knowing your vehicle is actively guarded around the clock.';
      }
    }

    // 5. Is it free? Pricing queries
    if (_matches(lower, ['free hai', 'kitna paisa', 'charge', 'cost', 'price', 'kitne ka', 'subscription', 'paisa lagega'])) {
      if (useHindi) {
        return 'Haanji bhai, bilkul 100% FREE hai! 🎉\n\n'
            'RaahMilo mobile app, iska live GPS tracking, Anti-Theft security shield, aur email alerts use karne ka koi bhi charge nahi hai. Koi hidden fee nahi hai, aap maze se bindass use kijiye!';
      } else {
        return 'Yes, absolutely! It is 100% completely FREE! 🎉\n\n'
            'The RaahMilo mobile app, real-time GPS tracking, Anti-Theft Shield, and email alert system are entirely free to use with zero hidden subscriptions or fees.';
      }
    }

    // 6. How to Arm / Lock vehicle
    if (_matches(lower, ['arm kaise', 'lock kaise', 'suraksha kaise', 'how to arm', 'how to lock', 'activate antitheft', 'chalu kaise'])) {
      if (useHindi) {
        return 'Gaadi ko lock (Arm) karna bohot aasaan hai dost:\n\n'
            '1️⃣ Niche diye gaye menu se **Anti-Theft** tab par tap karein.\n'
            '2️⃣ Bada sa **"Arm Vehicle"** ka blue button dabayein.\n\n'
            'Bas! Gaadi ka current GPS anchor point lock ho jayega. Ab agar gaadi hili toh turant siren bajega!';
      } else {
        return 'Arming your vehicle is super easy:\n\n'
            '1️⃣ Tap the **Anti-Theft** tab in the bottom navigation bar.\n'
            '2️⃣ Tap the large **"ARM VEHICLE"** button.\n\n'
            'That\'s all! Your vehicle\'s current GPS coordinate is instantly anchored. Any unauthorized movement will trigger the siren alarm immediately!';
      }
    }

    // 7. Alarm / Siren ringing: "Alarm band kaise karein?"
    if (_matches(lower, ['alarm band', 'siren band', 'shor band', 'stop alarm', 'silence siren', 'how to stop siren', 'baj raha'])) {
      if (useHindi) {
        return 'Ghabraiye mat! Alarm band karne ke 2 aasaan tareeqe hain:\n\n'
            '• **Top Banner:** Screen ke upar jo red emergency banner aa raha hai, uspe **"Silence"** daba dein.\n'
            '• **Anti-Theft Screen:** Anti-Theft screen me jakar **"Silence Alarm"** par tap karein.\n\n'
            'Siren turant chup ho jayega. Lekin ek baar check zaroor kar lein ki aapki gaadi surakshit jagah khadi hai!';
      } else {
        return 'No need to panic! You can silence the alarm in two quick ways:\n\n'
            '• **Emergency Banner:** Tap **"Silence"** on the red banner at the top of your screen.\n'
            '• **Anti-Theft Screen:** Open Anti-Theft and tap **"Silence Siren"**.\n\n'
            'The siren will stop immediately. Please do take a quick look to verify that your vehicle is safely parked!';
      }
    }

    // 8. Remote Engine Cut-off / Immobilizer
    if (_matches(lower, ['engine', 'immobilizer', 'ignition', 'gadi band', 'cut off', 'cutoff', 'remote stop'])) {
      if (useHindi) {
        return 'Remote Engine Cut-off ek powerful security feature hai:\n\n'
            'Agar kisi ne gaadi chura li ho, to aap Anti-Theft screen me **"Remote Engine Cut-off"** switch ko ON kar sakte hain. Isse gaadi ka ignition remotely immobilize ho jayega aur thief gaadi ko aage nahi le ja sakega!';
      } else {
        return 'The Remote Engine Immobilizer is an advanced defense feature:\n\n'
            'If you suspect unauthorized movement or theft, simply turn on **"Remote Engine Cut-off"** from the Anti-Theft screen. This sends an electronic kill-switch command to immobilize the vehicle ignition remotely!';
      }
    }

    // 9. GPS & Live Tracking queries
    if (_matches(lower, ['gps', 'location', 'live map', 'track nahi', 'accuracy', 'chal nahi raha', 'kahan hai'])) {
      if (useHindi) {
        return 'GPS live tracking ke liye 2 zaroori baatein dhyan rakhein:\n\n'
            '1. Phone settings me Location Permission ko **"Allow all the time"** par set karein.\n'
            '2. Gaadi agar basement ya underground parking me ho, to satellite signal thoda weak ho sakta hai. Open sky me aate hi exact location update hone lagegi.';
      } else {
        return 'For optimal GPS live tracking accuracy:\n\n'
            '1. Ensure Location Permission is set to **"Allow all the time"** in your phone settings.\n'
            '2. If your vehicle is in an underground parking garage, satellite signals can be temporarily faint. As soon as it enters open sky, coordinates update with pinpoint accuracy.';
      }
    }

    // 10. Politeness / Thanks
    if (_matches(lower, ['thank you', 'thanks', 'dhanyawad', 'shukriya', 'ok', 'theek hai', 'acha'])) {
      if (useHindi) {
        return 'Arey aapka bohot bohot swagat hai bhai! 😊 Aapki gaadi ki suraksha hamari sabse badi zimmedari hai. Agar koi aur sawal ho to main hamesha yahi hoon!';
      } else {
        return 'You\'re most welcome! 😊 Keeping your vehicle safe is our absolute top priority. If you ever have any other question, I\'m always right here to help!';
      }
    }

    // 11. Conversational Default Fallback (Empathetic & Human)
    if (useHindi) {
      return 'Main samajh gaya dost! 😊 Main aapki poori madad karne ke liye yahan hoon. Aap mujhse gaadi ki security, Anti-Theft shield, Siren alarm, ya Live tracking ke baare me kuch bhi poochh sakte hain.\n\nAgar aapko koi samasya ya complaint hai, toh batayein aur main turant humari Support Team ko escalate kar dunga!';
    } else {
      return 'I hear you! 😊 I\'m right here to support you with everything related to vehicle safety, Anti-Theft protection, Siren controls, and Live GPS tracking.\n\nIf you\'re facing any issue or need human assistance, just let me know and I will instantly escalate it to our operations desk!';
    }
  }

  static bool _matches(String text, List<String> keywords) {
    for (final k in keywords) {
      if (text.contains(k)) return true;
    }
    return false;
  }
}
