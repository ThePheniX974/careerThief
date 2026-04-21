'use strict';

// ─────────────────────────────────────────────────────────────────────────────
// Career Thief – UI Controller
// Reçoit les événements de career_modules_thief (GELUA) via guihooks.trigger()
// et affiche le prompt, la barre QTE et les feedbacks.
// ─────────────────────────────────────────────────────────────────────────────

angular.module('beamng.apps')

// ── Directive ─────────────────────────────────────────────────────────────────
.directive('careerThief', [function () {
  return {
    templateUrl : '/ui/modules/apps/careerThief/app.html',
    replace     : true,
    restrict    : 'EA',
    controller  : 'CareerThiefCtrl',
  };
}])

// ── Contrôleur ────────────────────────────────────────────────────────────────
.controller('CareerThiefCtrl', ['$scope', '$timeout', function ($scope, $timeout) {

  // ── État initial ────────────────────────────────────────────────────────────
  $scope.showPrompt    = false;
  $scope.qteActive     = false;
  $scope.feedbackVisible = false;
  $scope.onCooldown    = false;
  $scope.cooldownPct   = 100;

  // Prompt
  $scope.targetPartName = '';
  $scope.targetValue    = 0;

  // QTE
  $scope.qtePartName    = '';
  $scope.qtePos         = 0;       // position curseur (0–1)
  $scope.qteTimePct     = 100;     // temps restant en %
  $scope.successZone    = 0.18;    // largeur zone verte

  // Feedback
  $scope.feedbackClass  = '';
  $scope.feedbackIcon   = '';
  $scope.feedbackMsg    = '';
  $scope.feedbackValue  = 0;

  // Wanted
  $scope.wanted = { active: false, timeStr: '0:00' };

  // Timers internes
  var feedbackTimer    = null;
  var qteStartTime     = null;
  var qteDuration      = 4000; // ms
  var cooldownMax      = 1;
  var cooldownStart    = 0;

  // ── Helpers ─────────────────────────────────────────────────────────────────
  function pad2(n) {
    return n < 10 ? '0' + n : '' + n;
  }

  function formatTime(secs) {
    var s = Math.max(0, Math.floor(secs));
    return Math.floor(s / 60) + ':' + pad2(s % 60);
  }

  function cancelFeedback() {
    if (feedbackTimer) {
      $timeout.cancel(feedbackTimer);
      feedbackTimer = null;
    }
  }

  function showFeedback(cls, icon, msg, value, durationSec) {
    cancelFeedback();
    $scope.feedbackClass   = cls;
    $scope.feedbackIcon    = icon;
    $scope.feedbackMsg     = msg;
    $scope.feedbackValue   = value || 0;
    $scope.feedbackVisible = true;
    $scope.qteActive       = false;

    feedbackTimer = $timeout(function () {
      $scope.feedbackVisible = false;
    }, (durationSec || 3) * 1000);
  }

  // ── Gestionnaire central des événements GELUA ────────────────────────────────
  $scope.$on('careerThief_update', function (evt, d) {
    if (!d) return;

    switch (d.type) {

      // ── Cible détectée ─────────────────────────────────────────────────────
      case 'targetFound':
        $scope.showPrompt     = true;
        $scope.targetPartName = d.partName;
        $scope.targetValue    = d.value;
        $scope.onCooldown     = d.onCooldown;
        if (d.onCooldown && d.cooldown > 0) {
          cooldownMax   = d.cooldown;  // snapshot au début
          cooldownStart = Date.now();
          $scope.cooldownPct = 100;
        }
        if (d.wanted) {
          $scope.wanted.active  = true;
          $scope.wanted.timeStr = formatTime(d.wantedTime);
        }
        break;

      // ── Toutes les pièces déjà volées ─────────────────────────────────────
      case 'targetExhausted':
        $scope.showPrompt = false;
        break;

      // ── Aucun véhicule à portée ───────────────────────────────────────────
      case 'idle':
        $scope.showPrompt = false;
        if (d.wanted) {
          $scope.wanted.active  = true;
          $scope.wanted.timeStr = formatTime(d.wantedTime);
        }
        break;

      // ── QTE démarré ───────────────────────────────────────────────────────
      case 'qteStart':
        cancelFeedback();
        $scope.showPrompt     = false;
        $scope.feedbackVisible = false;
        $scope.qteActive      = true;
        $scope.qtePartName    = d.partName;
        $scope.qtePos         = 0;
        $scope.qteTimePct     = 100;
        $scope.successZone    = d.successZone || 0.18;
        qteDuration           = (d.duration || 4) * 1000;
        qteStartTime          = Date.now();
        break;

      // ── Tick du QTE : mise à jour curseur et timer ────────────────────────
      case 'qteTick':
        if ($scope.qteActive) {
          $scope.qtePos     = d.pos;
          var elapsed       = Date.now() - (qteStartTime || Date.now());
          $scope.qteTimePct = Math.max(0, 100 - (elapsed / qteDuration) * 100);
        }
        break;

      // ── Résultat QTE : succès ─────────────────────────────────────────────
      case 'qteSuccess':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(120);
        showFeedback('ct-success', '✓', d.partName + ' volé(e) !', d.value, 3.5);
        break;

      // ── Résultat QTE : raté ───────────────────────────────────────────────
      case 'qteFail':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(120);
        showFeedback('ct-fail', '✗', 'Raté ! Police alertée !', 0, 3);
        break;

      // ── QTE timeout ───────────────────────────────────────────────────────
      case 'qteTimeout':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(120);
        showFeedback('ct-fail', '⏱', 'Trop lent ! Police alertée !', 0, 3);
        break;

      // ── Début de l'état "recherché" ───────────────────────────────────────
      case 'wantedStart':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(d.duration);
        break;

      // ── Fin de l'état "recherché" ─────────────────────────────────────────
      case 'wantedEnd':
        $scope.wanted.active = false;
        break;

      // ── Cooldown actif ────────────────────────────────────────────────────
      case 'onCooldown':
        showFeedback('ct-warn', '⏳', 'Attendez ' + Math.ceil(d.remaining) + ' s...', 0, 1.8);
        break;

      // ── Pas de cible ──────────────────────────────────────────────────────
      case 'noTarget':
        showFeedback('ct-warn', '👁', 'Aucun véhicule à portée', 0, 1.8);
        break;

      // ── Plus de pièces disponibles ────────────────────────────────────────
      case 'noPartsLeft':
        showFeedback('ct-warn', '✖', 'Plus rien à voler ici', 0, 2.5);
        break;

      // ── Module prêt ───────────────────────────────────────────────────────
      case 'moduleReady':
        // Réinitialiser l'UI
        $scope.showPrompt      = false;
        $scope.qteActive       = false;
        $scope.feedbackVisible = false;
        $scope.wanted.active   = false;
        break;

      // ── Masquer tout ──────────────────────────────────────────────────────
      case 'hide':
        cancelFeedback();
        $scope.showPrompt      = false;
        $scope.qteActive       = false;
        $scope.feedbackVisible = false;
        $scope.wanted.active   = false;
        break;
    }
  });

  // ── Nettoyage ────────────────────────────────────────────────────────────────
  $scope.$on('$destroy', function () {
    cancelFeedback();
  });

}]);
