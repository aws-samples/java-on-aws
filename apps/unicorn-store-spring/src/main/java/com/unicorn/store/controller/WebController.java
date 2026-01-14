package com.unicorn.store.controller;

import com.unicorn.store.config.ReleaseInfo;
import com.unicorn.store.model.Unicorn;
import com.unicorn.store.service.UnicornService;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;

@Controller
@RequestMapping("/webui")
public class WebController {

    private final UnicornService unicornService;
    private final ReleaseInfo releaseInfo;

    public WebController(UnicornService unicornService, ReleaseInfo releaseInfo) {
        this.unicornService = unicornService;
        this.releaseInfo = releaseInfo;
    }

    @GetMapping
    public String index(Model model) {
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        model.addAttribute("newUnicorn", new Unicorn());
        model.addAttribute("version", releaseInfo.getVersion());
        model.addAttribute("deploymentTime", releaseInfo.getDeploymentTime());
        model.addAttribute("commit", releaseInfo.getCommit());
        model.addAttribute("pod", releaseInfo.getPod());
        return "unicorns";
    }

    @GetMapping("/list")
    public String listUnicorns(Model model) {
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }

    @PostMapping("/create")
    public String createUnicorn(@ModelAttribute Unicorn unicorn, Model model) {
        unicornService.createUnicorn(unicorn);
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }

    @GetMapping("/edit/{id}")
    public String editForm(@PathVariable String id, Model model) {
        model.addAttribute("unicorn", unicornService.getUnicorn(id));
        return "fragments/edit-form :: editForm";
    }

    @PostMapping("/update/{id}")
    public String updateUnicorn(@PathVariable String id, @ModelAttribute Unicorn unicorn, Model model) {
        unicornService.updateUnicorn(unicorn, id);
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }

    @DeleteMapping("/delete/{id}")
    public String deleteUnicorn(@PathVariable String id, Model model) {
        unicornService.deleteUnicorn(id);
        model.addAttribute("unicorns", unicornService.getAllUnicorns());
        return "fragments/unicorn-table :: unicornTable";
    }
}
