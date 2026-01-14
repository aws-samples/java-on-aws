package com.unicorn.store.controller;

import com.unicorn.store.config.ReleaseInfo;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class IndexController {

    private final ReleaseInfo releaseInfo;

    public IndexController(ReleaseInfo releaseInfo) {
        this.releaseInfo = releaseInfo;
    }

    @GetMapping("/")
    public String index(Model model) {
        model.addAttribute("version", releaseInfo.getVersion());
        model.addAttribute("deploymentTime", releaseInfo.getDeploymentTime());
        model.addAttribute("commit", releaseInfo.getCommit());
        model.addAttribute("pod", releaseInfo.getPod());
        return "index";
    }
}
