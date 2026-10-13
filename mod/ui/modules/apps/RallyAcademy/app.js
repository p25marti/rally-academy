angular.module('beamng.apps').directive('rallyAcademy', ['bngApi', function (bngApi) {
  return {
    restrict: 'EA',
    replace: true,
    template: [
      '<div class="rally-academy-app" style="height:100%;background:rgba(13,21,30,.93);color:#f8fafc;padding:12px;overflow:auto;font-family:sans-serif;font-size:13px;border-radius:8px;box-sizing:border-box">',
      '<div style="font-weight:700;font-size:17px;margin-bottom:10px">RALLY ACADEMY <span style="font-size:11px;color:#94a3b8">ALPHA</span></div>',
      '<select ng-model="selectedId" ng-options="x.id as (x.id + \' · \' + x.title) for x in vm.lessons" ng-change="choose()" style="width:100%;font-size:12px;padding:5px"></select>',
      '<p ng-if="vm.lesson" style="color:#dbeafe;line-height:1.3">{{vm.lesson.instructions}}</p>',
      '<div style="background:#1e293b;padding:6px;border-radius:4px;margin:8px 0">{{vm.phase}} · {{vm.successes}}/{{vm.attempts}} successful · target {{vm.required}}/{{vm.target}}</div>',
      '<div style="display:flex;gap:5px;flex-wrap:wrap">',
      '<button ng-click="cmd(\'markStart\')">Mark start</button>',
      '<button ng-click="cmd(\'markFinish\')">Mark finish</button>',
      '<button ng-click="cmd(\'retry\')">↻ Retry</button>',
      '<button ng-click="cmd(\'recordAttempt\',true)">✓ Pass</button>',
      '<button ng-click="cmd(\'recordAttempt\',false)">✕ Miss</button>',
      '</div>',
      '<p style="color:#cbd5e1;margin-bottom:3px">{{vm.reason}}</p>',
      '<p style="color:#64748b;font-size:11px">{{vm.prototypeWarning}}</p>',
      '</div>'
    ].join(''),
    link: function (scope) {
      scope.vm = { lessons: [], phase: 'loading', successes: 0, attempts: 0 };
      scope.selectedId = null;
      scope.cmd = function (name, arg) {
        var methods = {markStart:1, markFinish:1, retry:1, recordAttempt:1};
        if (!methods[name]) return;
        var args = name === 'recordAttempt' ? (arg ? 'true' : 'false') : '';
        bngApi.engineLua('if extensions.rallyAcademy then extensions.rallyAcademy.' + name + '(' + args + ') end');
      };
      scope.choose = function () {
        if (scope.selectedId) bngApi.engineLua('extensions.rallyAcademy.select(' + JSON.stringify(scope.selectedId) + ')');
      };
      scope.$on('rallyAcademyState', function (event, data) {
        scope.vm = Object.assign({}, scope.vm, data);
        if (data.selected) scope.selectedId = data.selected;
        else if (!scope.selectedId && data.lessons && data.lessons.length) {
          scope.selectedId = data.lessons[0].id;
          scope.choose();
        }
      });
      // Keeping Lua authoritative also lets the HUD be closed/reopened without losing the session.
      bngApi.engineLua("extensions.load('rallyAcademy'); extensions.rallyAcademy.publish()");
    }
  };
}]);
