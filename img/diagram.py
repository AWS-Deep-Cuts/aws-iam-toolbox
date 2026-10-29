#!/usr/bin/env python3
"""構成図を生成する（pip install diagrams と graphviz が必要）: python3 img/diagram.py"""
import os
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.general import User
from diagrams.aws.security import IAM, IAMPermissions, IAMRole

FONT = os.environ.get("DIAGRAM_FONT", "WenQuanYi Zen Hei")
ATTR = {"fontname": FONT}
os.chdir(os.path.dirname(os.path.abspath(__file__)))

with Diagram("", show=False, filename="architecture", outformat="png", direction="LR",
             graph_attr={**ATTR, "pad": "0.6", "nodesep": "0.9", "ranksep": "1.3", "splines": "spline"},
             node_attr={**ATTR, "fontsize": "12"}, edge_attr={**ATTR, "fontsize": "11"}):
    you = User("あなた\n(CloudShell, 管理者)")
    troubleshooter = IAM("IAM Access Troubleshooter\n（authorization ID から\n評価の過程を見る）")
    with Cluster("探偵（source ./detective.sh で変身）", graph_attr=ATTR):
        detective = IAMRole("探偵ロール\nタグ clearance=rookie\n呪い（インライン Deny）\nアクセス許可の境界")
        license_ = IAMPermissions("探偵免許（管理ポリシー）\n条件: clearance=top-secret")
    vault = IAMPermissions("金庫（IAM 管理ポリシー）\naws-deepcuts-vault\n説明文に修了証が刻まれている")
    you >> Edge(label="sts:AssumeRole") >> detective
    detective >> Edge(label="iam:GetPolicy\n→ AccessDenied + authorization ID", color="firebrick", fontcolor="firebrick") >> vault
    license_ >> Edge(label="アタッチ（鍵 2）", style="dashed") >> detective
    you >> Edge(label="真犯人を調べて、\nポリシーを直す", style="dotted") >> troubleshooter
